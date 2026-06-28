#ifndef SPEAKEASY_CORE_H
#define SPEAKEASY_CORE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    APP_STATE_NEEDS_MODEL = 0,
    APP_STATE_READY = 1,
    APP_STATE_RECORDING = 2,
    APP_STATE_TRANSCRIBING = 3,
    APP_STATE_CLEANING_UP = 4
} AppState;

typedef enum {
    APP_EVENT_MODEL_LOADED = 0,
    APP_EVENT_MODEL_REMOVED = 1,
    APP_EVENT_START_RECORDING_REQUESTED = 2,
    APP_EVENT_STOP_RECORDING_REQUESTED = 3,
    APP_EVENT_TRANSCRIPTION_COMPLETED = 4,
    APP_EVENT_TRANSCRIPTION_FAILED = 5,
    APP_EVENT_NO_AUDIO_RECORDED = 6,
    APP_EVENT_CANCELLATION_REQUESTED = 7,
    APP_EVENT_CLEANUP_STARTED = 8,
    APP_EVENT_CLEANUP_COMPLETED = 9,
    APP_EVENT_CLEANUP_FAILED = 10
} AppEvent;

// State machine
uint8_t state_machine_transition(uint8_t current_state, uint8_t event);
bool state_machine_can_start_recording(uint8_t state);
bool state_machine_is_busy(uint8_t state);
bool state_machine_needs_setup(uint8_t state);

// Whisper context lifecycle
typedef struct WhisperContext WhisperContext;
WhisperContext* whisper_context_init(const char* model_path);
void whisper_context_destroy(WhisperContext* ctx);

// Audio transcription (local via whisper.cpp)
char* transcribe_audio_blocking(
    const WhisperContext* ctx,
    const char* audio_file_path
);

void free_rust_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif // SPEAKEASY_CORE_H
