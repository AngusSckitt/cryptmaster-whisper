// cmwhisper: a small, stable C interface between the Cryptmaster Whisper mod (C#) and a current whisper.cpp.
// Compiled against whisper.cpp's own headers, so the mod never mirrors whisper.cpp's C structs (they change
// between versions); updating whisper.cpp only needs a rebuild. Part of Cryptmaster Whisper (GPL-3.0).
#include <windows.h>
#include <string>
#include <cstring>
#include <mutex>
#include "whisper.h"
#include "ggml-backend.h"

#define CMW_API extern "C" __declspec(dllexport)

typedef void (*cmw_log_fn)(int level, const char * text);
static cmw_log_fn g_log = nullptr;
static std::once_flag g_backends_loaded;

static void forward_log(enum ggml_log_level level, const char * text, void *) {
    if (g_log && text) g_log((int) level, text);
}

static std::string to_utf8(const std::wstring & w) {
    if (w.empty()) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int) w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, 0);
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int) w.size(), &s[0], n, nullptr, nullptr);
    return s;
}

// Folder of this DLL: ggml loads its backends (CPU variants, Vulkan, CUDA) from there. Wide characters, so a
// game folder with accents (or any non-ANSI name) still works.
static std::wstring own_folder() {
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCWSTR) &own_folder, &self);
    std::wstring s(32768, 0); // long paths too; on the heap (game threads may have small stacks)
    s.resize(GetModuleFileNameW(self, &s[0], (DWORD) s.size()));
    size_t slash = s.find_last_of(L"\\/");
    return slash == std::wstring::npos ? std::wstring(L".") : s.substr(0, slash);
}

// GPU runtimes a backend imports (e.g. CUDA's cudart/cublas, when the optional CUDA files were installed next
// to this DLL). The game's .exe lives elsewhere, so Windows wouldn't find them; loading them first by full
// path lets the backend's imports resolve, without changing the process's DLL search path (and without
// LOAD_WITH_ALTERED_SEARCH_PATH, which breaks when the folder name has a ";").
static void preload_runtimes(const std::wstring & folder) {
    const wchar_t * patterns[] = { L"cudart64_*.dll", L"cublasLt64_*.dll", L"cublas64_*.dll", L"nvrtc-builtins64_*.dll", L"nvrtc64_*.dll" };
    for (const wchar_t * pattern : patterns) {
        WIN32_FIND_DATAW found;
        HANDLE h = FindFirstFileW((folder + L"\\" + pattern).c_str(), &found);
        if (h == INVALID_HANDLE_VALUE) continue;
        do {
            LoadLibraryExW((folder + L"\\" + found.cFileName).c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        } while (FindNextFileW(h, &found));
        FindClose(h);
    }
}

// Once per process, whichever call comes first (model loading and speech detection start on different threads).
static void load_backends() {
    std::call_once(g_backends_loaded, [] {
        std::wstring folder = own_folder();
        preload_runtimes(folder);
        ggml_backend_load_all_from_path(to_utf8(folder).c_str()); // ggml reads the path as UTF-8
    });
}

CMW_API int cmw_interface_version() { return 1; }

CMW_API void cmw_set_log(cmw_log_fn fn) {
    g_log = fn;
    whisper_log_set(fn ? forward_log : nullptr, nullptr);
}

CMW_API const char * cmw_system_info() { return whisper_print_system_info(); }

// Loads a model; use_gpu = 0 forces the CPU. Returns null on failure.
CMW_API void * cmw_init(const char * model_path, int use_gpu) {
    load_backends();
    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = use_gpu != 0;
    return whisper_init_from_file_with_params(model_path, cparams);
}

// The GPU whisper.cpp will use (the first one ggml found), written to name; returns its free memory in MB,
// or -1 if there is no usable GPU (recognition then runs on the CPU).
CMW_API int cmw_gpu(char * name, int name_size) {
    load_backends();
    if (name && name_size > 0) name[0] = 0;
    for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
        ggml_backend_dev_t dev = ggml_backend_dev_get(i);
        if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU) {
            size_t free_mem = 0, total_mem = 0;
            ggml_backend_dev_memory(dev, &free_mem, &total_mem);
            if (name && name_size > 0) strncpy_s(name, name_size, ggml_backend_dev_description(dev), _TRUNCATE);
            return (int) (free_mem >> 20);
        }
    }
    return -1;
}

// ---- Silero voice activity detection (speech vs. noise, music, typing...) ----

// Loads a Silero VAD model (ggml); it runs on the CPU, next to recognition. Null on failure.
CMW_API void * cmw_vad_init(const char * model_path) {
    load_backends();
    whisper_vad_context_params p = whisper_vad_default_context_params();
    p.n_threads = 1;
    p.use_gpu = false;
    return whisper_vad_init_from_file_with_params(model_path, p);
}

// Streaming: feeds the newest audio (16 kHz mono; a multiple of 512 samples) and returns the highest speech
// probability among the windows it covered (0..1), or -1 on failure. The network keeps its memory between
// calls; call cmw_vad_reset between utterances.
CMW_API float cmw_vad_prob(void * vctx, const float * samples, int n_samples) {
    if (!vctx || n_samples <= 0) return -1.0f;
    if (!whisper_vad_detect_speech_no_reset((whisper_vad_context *) vctx, samples, n_samples)) return -1.0f;
    int n = whisper_vad_n_probs((whisper_vad_context *) vctx);
    const float * probs = whisper_vad_probs((whisper_vad_context *) vctx);
    float best = 0.0f;
    for (int i = 0; i < n; i++) if (probs[i] > best) best = probs[i];
    return best;
}

CMW_API void cmw_vad_reset(void * vctx) {
    if (vctx) whisper_vad_reset_state((whisper_vad_context *) vctx);
}

CMW_API void cmw_vad_free(void * vctx) {
    if (vctx) whisper_vad_free((whisper_vad_context *) vctx);
}

CMW_API void cmw_free(void * ctx) {
    if (ctx) whisper_free((whisper_context *) ctx);
}

// Transcribes one utterance (16 kHz mono float). Writes UTF-8 text to out; returns 0 on success.
// no_speech receives Whisper's probability that the audio held no speech (0..1).
CMW_API int cmw_transcribe(void * ctx, const float * samples, int n_samples, const char * language,
                           const char * prompt_utf8, int audio_ctx, int n_threads, int max_tokens,
                           float temperature_inc, char * out, int out_size, float * no_speech) {
    if (!ctx || !out || out_size <= 0) return -1;
    whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.n_threads        = n_threads > 0 ? n_threads : 4;
    p.language         = language && *language ? language : "auto";
    p.no_context       = true;
    p.single_segment   = true;
    p.no_timestamps    = true;
    p.print_progress   = false;
    p.print_realtime   = false;
    p.print_timestamps = false;
    p.print_special    = false;
    p.suppress_nst     = true;
    p.max_tokens       = max_tokens;
    p.audio_ctx        = audio_ctx;
    p.temperature_inc  = temperature_inc;
    p.initial_prompt   = prompt_utf8 && *prompt_utf8 ? prompt_utf8 : nullptr;

    out[0] = 0;
    if (no_speech) *no_speech = 0.0f;
    int result = whisper_full((whisper_context *) ctx, p, samples, n_samples);
    if (result != 0) return result;

    std::string text;
    int segments = whisper_full_n_segments((whisper_context *) ctx);
    for (int i = 0; i < segments; i++) {
        text += whisper_full_get_segment_text((whisper_context *) ctx, i);
        if (no_speech && i == 0) *no_speech = whisper_full_get_segment_no_speech_prob((whisper_context *) ctx, i);
    }
    strncpy_s(out, out_size, text.c_str(), _TRUNCATE);
    return 0;
}
