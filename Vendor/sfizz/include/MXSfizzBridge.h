//
//  MXSfizzBridge.h
//  The C surface an ObjC++ sfizz wrapper must implement.
//
//  Kept pure C so the implementation file can be ObjC++ and hold a
//  `sfizz::Sfizz` instance without any Swift type crossing the boundary. The
//  render entry point must be callable from the audio thread, which means the
//  implementation may not allocate, lock, or throw inside it.
//
//  Swift consumes this through `MXSFZEngine`; see Vendor/sfizz/README.md.
//

#ifndef MXSfizzBridge_h
#define MXSfizzBridge_h

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MXSfizzHandle MXSfizzHandle;

typedef enum {
    MXSfizzOK = 0,
    MXSfizzFileNotFound = 1,
    MXSfizzParseFailed = 2,
    MXSfizzOutOfMemory = 3,
} MXSfizzStatus;

/// Lifetime. Both are control-thread only.
MXSfizzHandle * _Nullable mx_sfizz_create(double sampleRate, int32_t maxBlockSize);
void mx_sfizz_destroy(MXSfizzHandle * _Nonnull handle);

/// Loading. Control thread only; may allocate and read from disk.
MXSfizzStatus mx_sfizz_load_file(MXSfizzHandle * _Nonnull handle,
                                 const char * _Nonnull path);

/// Last error text for the calling thread. Valid until the next bridge call.
const char * _Nullable mx_sfizz_last_error(MXSfizzHandle * _Nonnull handle);

/// Configuration. Control thread only.
void mx_sfizz_set_sample_rate(MXSfizzHandle * _Nonnull handle, double sampleRate);
void mx_sfizz_set_block_size(MXSfizzHandle * _Nonnull handle, int32_t frames);
void mx_sfizz_set_polyphony(MXSfizzHandle * _Nonnull handle, int32_t voices);

/// Events. Lock-free; safe from the control thread while rendering.
/// `frameOffset` positions the event inside the next render block.
void mx_sfizz_note_on(MXSfizzHandle * _Nonnull handle,
                      int32_t frameOffset, int32_t note, int32_t velocity);
void mx_sfizz_note_off(MXSfizzHandle * _Nonnull handle,
                       int32_t frameOffset, int32_t note, int32_t velocity);
void mx_sfizz_cc(MXSfizzHandle * _Nonnull handle,
                 int32_t frameOffset, int32_t cc, float value);
void mx_sfizz_all_sound_off(MXSfizzHandle * _Nonnull handle);

/// Render. AUDIO THREAD ONLY. Must not allocate, lock, or block.
/// Writes `frameCount` frames into two non-interleaved channel buffers.
void mx_sfizz_render(MXSfizzHandle * _Nonnull handle,
                     float * _Nonnull left,
                     float * _Nonnull right,
                     int32_t frameCount);

/// Introspection. Control thread only.
int32_t mx_sfizz_active_voices(const MXSfizzHandle * _Nonnull handle);
int32_t mx_sfizz_region_count(const MXSfizzHandle * _Nonnull handle);
size_t  mx_sfizz_resident_bytes(const MXSfizzHandle * _Nonnull handle);

#ifdef __cplusplus
}
#endif

#endif /* MXSfizzBridge_h */
