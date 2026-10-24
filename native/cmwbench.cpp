// cmwbench: times a Whisper model on this PC, for the installer's model recommendation.
// Usage: cmwbench <model.bin> [--cpu] [--ctx 256] [--runs 3] [--out result.txt]
// Prints key=value lines: device, vram_free_mb, load_ms, median_ms (2 s of quiet noise, greedy, one segment).
// Part of Cryptmaster Whisper (GPL-3.0).
#define NOMINMAX
#include <windows.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include "whisper.h"
#include "ggml-backend.h"

static void quiet(enum ggml_log_level, const char *, void *) {}

static std::string to_utf8(const std::wstring & w) {
    if (w.empty()) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int) w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, 0);
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int) w.size(), &s[0], n, nullptr, nullptr);
    return s;
}

// UTF-8, which is what ggml and whisper.cpp expect for paths (wide arguments: folders with accents work).
static std::string exe_folder() {
    std::wstring s(32768, 0);
    s.resize(GetModuleFileNameW(nullptr, &s[0], (DWORD) s.size()));
    return to_utf8(s.substr(0, s.find_last_of(L"\\/")));
}

int wmain(int argc, wchar_t ** argv) {
    if (argc < 2) { fprintf(stderr, "usage: cmwbench <model> [--cpu] [--ctx N] [--runs N] [--out file]\n"); return 2; }
    std::string model_path = to_utf8(argv[1]);
    const char * model = model_path.c_str();
    const wchar_t * out = nullptr;
    bool cpu = false; int ctx = 256, runs = 3;
    for (int i = 2; i < argc; i++) {
        if (!wcscmp(argv[i], L"--cpu")) cpu = true;
        else if (!wcscmp(argv[i], L"--ctx") && i + 1 < argc) ctx = _wtoi(argv[++i]);
        else if (!wcscmp(argv[i], L"--runs") && i + 1 < argc) runs = _wtoi(argv[++i]);
        else if (!wcscmp(argv[i], L"--out") && i + 1 < argc) out = argv[++i];
    }
    runs = std::max(1, runs); // the medians below need at least one run
    ctx = std::max(0, ctx);   // 0 = whisper.cpp's full window
    // --out: the result goes to a file instead of the console (the installer runs this without admin rights,
    // where it can't capture the output).
    if (out && !_wfreopen(out, L"w", stdout)) return 3;
    whisper_log_set(quiet, nullptr);
    ggml_backend_load_all_from_path(exe_folder().c_str());

    // The GPU whisper.cpp would use (the first one), and its free memory.
    std::string device = "CPU", backend = "CPU";
    size_t free_mem = 0, total_mem = 0;
    if (!cpu) {
        for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
            ggml_backend_dev_t dev = ggml_backend_dev_get(i);
            if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU) {
                device = ggml_backend_dev_description(dev);
                backend = ggml_backend_dev_name(dev); // e.g. Vulkan0, CUDA0
                ggml_backend_dev_memory(dev, &free_mem, &total_mem);
                break;
            }
        }
    }
    printf("device=%s\nbackend=%s\nvram_free_mb=%zu\nvram_total_mb=%zu\n", device.c_str(), backend.c_str(), free_mem >> 20, total_mem >> 20);

    auto t0 = std::chrono::steady_clock::now();
    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = !cpu;
    whisper_context * wctx = whisper_init_from_file_with_params(model, cparams);
    if (!wctx) { printf("error=load failed\n"); return 1; }
    long long load = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    printf("load_ms=%lld\n", load);

    std::vector<float> audio(32000);
    unsigned seed = 1;
    for (float & s : audio) { seed = seed * 1103515245u + 12345u; s = ((seed >> 16) % 2000 / 1000.0f - 1.0f) * 0.01f; }

    whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    SYSTEM_INFO si; GetSystemInfo(&si);
    p.n_threads = std::max(1, std::min(4, (int) si.dwNumberOfProcessors - 1));
    p.language = "en"; p.no_context = true; p.single_segment = true; p.no_timestamps = true;
    p.print_progress = p.print_realtime = p.print_timestamps = p.print_special = false;
    p.suppress_nst = true; p.max_tokens = 24; p.audio_ctx = ctx; p.temperature_inc = 0.0f;

    whisper_full(wctx, p, audio.data(), (int) audio.size()); // warm-up
    std::vector<long long> times;
    for (int r = 0; r < runs; r++) {
        auto a = std::chrono::steady_clock::now();
        whisper_full(wctx, p, audio.data(), (int) audio.size());
        times.push_back(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - a).count());
    }
    std::sort(times.begin(), times.end());
    printf("median_ms=%lld\n", times[times.size() / 2]);

    // The encoder alone (mel + encode, at the audio_ctx set by the runs above): the same cost whatever the
    // audio says, unlike decoding, so it's what the estimates for other models scale from.
    std::vector<double> enc;
    for (int r = 0; r < runs; r++) {
        auto a = std::chrono::steady_clock::now();
        whisper_pcm_to_mel(wctx, audio.data(), (int) audio.size(), p.n_threads);
        whisper_encode(wctx, 0, p.n_threads);
        enc.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - a).count());
    }
    std::sort(enc.begin(), enc.end());
    printf("encode_ms=%.1f\nencode_us=%lld\n", enc[enc.size() / 2], (long long) (enc[enc.size() / 2] * 1000.0));
    whisper_free(wctx);
    return 0;
}
