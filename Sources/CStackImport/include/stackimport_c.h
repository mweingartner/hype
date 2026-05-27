#ifndef STACKIMPORT_C_H
#define STACKIMPORT_C_H

#include <stddef.h>
#include <stdint.h>

#include "stackimport_version.h"

#ifndef STACKIMPORT_API
#if defined(_WIN32) && defined(STACKIMPORT_SHARED)
#if defined(STACKIMPORT_BUILD_SHARED)
#define STACKIMPORT_API __declspec(dllexport)
#else
#define STACKIMPORT_API __declspec(dllimport)
#endif
#elif defined(__GNUC__) && defined(STACKIMPORT_BUILD_SHARED)
#define STACKIMPORT_API __attribute__((visibility("default")))
#else
#define STACKIMPORT_API
#endif
#endif

#ifndef STACKIMPORT_CALL
#if defined(_WIN32)
#define STACKIMPORT_CALL __cdecl
#else
#define STACKIMPORT_CALL
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define STACKIMPORT_API_VERSION 7u

typedef struct stackimport_context stackimport_context;

typedef enum stackimport_status {
	STACKIMPORT_STATUS_OK = 0,
	STACKIMPORT_STATUS_INVALID_ARGUMENT = 1,
	STACKIMPORT_STATUS_ALLOCATION_FAILED = 2,
	STACKIMPORT_STATUS_IMPORT_FAILED = 3,
	STACKIMPORT_STATUS_UNSUPPORTED_OPTION = 4,
	STACKIMPORT_STATUS_ABI_MISMATCH = 5
} stackimport_status;

typedef enum stackimport_import_flags {
	STACKIMPORT_IMPORT_DUMP_RAW_BLOCKS = 1u << 0,
	STACKIMPORT_IMPORT_NO_STATUS = 1u << 1,
	STACKIMPORT_IMPORT_NO_PROGRESS = 1u << 2,
	STACKIMPORT_IMPORT_RAW_GRAPHICS = 1u << 3
} stackimport_import_flags;

typedef void* (STACKIMPORT_CALL *stackimport_allocate_fn)(size_t size, size_t alignment, void* user_data);
typedef void (STACKIMPORT_CALL *stackimport_deallocate_fn)(void* ptr, void* user_data);
typedef void (STACKIMPORT_CALL *stackimport_message_fn)(uint32_t severity, const char* message, void* user_data);

typedef void* stackimport_file_handle;
typedef stackimport_file_handle (STACKIMPORT_CALL *stackimport_open_file_fn)(const char* path, const char* mode, void* user_data);
typedef size_t (STACKIMPORT_CALL *stackimport_read_file_fn)(stackimport_file_handle file, void* data, size_t size, void* user_data);
typedef size_t (STACKIMPORT_CALL *stackimport_write_file_fn)(stackimport_file_handle file, const void* data, size_t size, void* user_data);
typedef int (STACKIMPORT_CALL *stackimport_close_file_fn)(stackimport_file_handle file, void* user_data);
typedef int (STACKIMPORT_CALL *stackimport_make_directory_fn)(const char* path, void* user_data);

typedef enum stackimport_resource_payload_format {
	STACKIMPORT_RESOURCE_PAYLOAD_NATIVE = 0,
	STACKIMPORT_RESOURCE_PAYLOAD_RGBA32 = 1,
	STACKIMPORT_RESOURCE_PAYLOAD_JSON_UTF8 = 2,
	STACKIMPORT_RESOURCE_PAYLOAD_TEXT_UTF8 = 3,
	STACKIMPORT_RESOURCE_PAYLOAD_BINARY = 4
} stackimport_resource_payload_format;

typedef enum stackimport_resource_payload_flags {
	STACKIMPORT_RESOURCE_PAYLOADS_NONE = 0,
	STACKIMPORT_RESOURCE_PAYLOADS_NATIVE = 1u << 0,
	STACKIMPORT_RESOURCE_PAYLOADS_CONVERTED = 1u << 1,
	STACKIMPORT_RESOURCE_PAYLOADS_ALL = STACKIMPORT_RESOURCE_PAYLOADS_NATIVE | STACKIMPORT_RESOURCE_PAYLOADS_CONVERTED
} stackimport_resource_payload_flags;

/*
 * Caller-provided callbacks are invoked synchronously and must not unwind across
 * the StackImport C ABI boundary. Report failure by returning a null handle,
 * short read/write, non-zero close/mkdir result, or 0 from resource callbacks.
 */

typedef struct stackimport_resource_payload {
	uint32_t struct_size;
	char type[4];
	int32_t id;
	uint32_t resource_flags;
	uint32_t order;
	const void* name;
	size_t name_size;
	size_t native_size;
	uint32_t format;
	uint32_t variant_index;
	uint32_t width;
	uint32_t height;
	uint32_t row_bytes;
	int32_t hotspot_x;
	int32_t hotspot_y;
	const char* media_type;
	const char* description;
	size_t payload_size;
} stackimport_resource_payload;

/*
 * Resource callbacks are synchronous. Pointers in stackimport_resource_payload,
 * including name and payload data, are valid only for the callback invocation.
 * resource_wants is called before resource_payload; return 0 to skip delivery.
 */
typedef int (STACKIMPORT_CALL *stackimport_resource_wants_fn)(const stackimport_resource_payload* payload, void* user_data);
typedef int (STACKIMPORT_CALL *stackimport_resource_payload_fn)(const stackimport_resource_payload* payload, const void* data, size_t size, void* user_data);

typedef enum stackimport_message_severity {
	STACKIMPORT_MESSAGE_INFO = 0,
	STACKIMPORT_MESSAGE_WARNING = 1,
	STACKIMPORT_MESSAGE_ERROR = 2,
	STACKIMPORT_MESSAGE_FATAL = 3
} stackimport_message_severity;

typedef enum stackimport_log_category {
	STACKIMPORT_LOG_GENERAL = 0,
	STACKIMPORT_LOG_STATUS = 1,
	STACKIMPORT_LOG_PROGRESS = 2,
	STACKIMPORT_LOG_WARNING = 3,
	STACKIMPORT_LOG_ERROR = 4,
	STACKIMPORT_LOG_FATAL = 5
} stackimport_log_category;

typedef struct stackimport_log_record {
	uint32_t struct_size;
	uint32_t severity;
	uint32_t category;
	const char* message;
	const char* detail;
} stackimport_log_record;

typedef void (STACKIMPORT_CALL *stackimport_log_fn)(const stackimport_log_record* record, void* user_data);

typedef struct stackimport_allocator {
	uint32_t struct_size;
	stackimport_allocate_fn allocate;
	stackimport_deallocate_fn deallocate;
	void* user_data;
} stackimport_allocator;

typedef struct stackimport_log_handler {
	uint32_t struct_size;
	stackimport_log_fn log;
	/* Optional fallback for callers that only need severity + message. */
	stackimport_message_fn message;
	void* user_data;
} stackimport_log_handler;

typedef struct stackimport_platform {
	uint32_t struct_size;
	stackimport_allocate_fn allocate;
	stackimport_deallocate_fn deallocate;
	stackimport_message_fn message;
	stackimport_open_file_fn open_file;
	stackimport_read_file_fn read_file;
	stackimport_write_file_fn write_file;
	stackimport_close_file_fn close_file;
	stackimport_make_directory_fn make_directory;
	void* user_data;
} stackimport_platform;

typedef struct stackimport_import_options {
	uint32_t struct_size;
	uint32_t flags;
	/* Callers own path resolution and output package naming. */
	const char* input_path;
	const char* output_package_path;
	/* Optional native/converted resource payload stream. */
	uint32_t resource_payload_flags;
	stackimport_resource_wants_fn resource_wants;
	stackimport_resource_payload_fn resource_payload;
	void* resource_user_data;
} stackimport_import_options;

STACKIMPORT_API uint32_t STACKIMPORT_CALL stackimport_api_version(void);

STACKIMPORT_API const char* STACKIMPORT_CALL stackimport_version_string(void);

STACKIMPORT_API uint32_t STACKIMPORT_CALL stackimport_version_packed(void);

STACKIMPORT_API const char* STACKIMPORT_CALL stackimport_status_string(stackimport_status status);

/* Initialize public structs before filling caller-owned fields. */
STACKIMPORT_API void STACKIMPORT_CALL stackimport_allocator_init(stackimport_allocator* allocator);
STACKIMPORT_API void STACKIMPORT_CALL stackimport_log_handler_init(stackimport_log_handler* handler);
STACKIMPORT_API void STACKIMPORT_CALL stackimport_platform_init(stackimport_platform* platform);
STACKIMPORT_API void STACKIMPORT_CALL stackimport_import_options_init(stackimport_import_options* options);

STACKIMPORT_API size_t STACKIMPORT_CALL stackimport_context_size(void);
STACKIMPORT_API size_t STACKIMPORT_CALL stackimport_context_alignment(void);
STACKIMPORT_API uint32_t STACKIMPORT_CALL stackimport_context_abi_signature(void);

STACKIMPORT_API stackimport_status STACKIMPORT_CALL stackimport_context_init(
	void* storage,
	size_t storage_size,
	stackimport_context** out_context);

STACKIMPORT_API stackimport_status STACKIMPORT_CALL stackimport_context_init_with_platform(
	void* storage,
	size_t storage_size,
	const stackimport_platform* platform,
	stackimport_context** out_context);

STACKIMPORT_API stackimport_status STACKIMPORT_CALL stackimport_context_init_with_log_handler(
	void* storage,
	size_t storage_size,
	const stackimport_log_handler* handler,
	stackimport_context** out_context);

STACKIMPORT_API void STACKIMPORT_CALL stackimport_context_deinit(stackimport_context* context);

STACKIMPORT_API stackimport_status STACKIMPORT_CALL stackimport_context_create(
	const stackimport_allocator* allocator,
	stackimport_context** out_context);

STACKIMPORT_API stackimport_status STACKIMPORT_CALL stackimport_context_create_with_platform(
	const stackimport_platform* platform,
	stackimport_context** out_context);

STACKIMPORT_API stackimport_status STACKIMPORT_CALL stackimport_context_create_with_log_handler(
	const stackimport_log_handler* handler,
	stackimport_context** out_context);

STACKIMPORT_API void STACKIMPORT_CALL stackimport_context_destroy(stackimport_context* context);

STACKIMPORT_API stackimport_status STACKIMPORT_CALL stackimport_import(
	stackimport_context* context,
	const stackimport_import_options* options);

/*
 * Standalone snd-to-WAV conversion. Does not require a context or platform
 * scope. Pass wav_buffer = NULL and wav_capacity = 0 to query the required WAV
 * byte size without writing output. Otherwise returns WAV size on success and 0
 * on failure. On failure, sets *out_error to a string that remains valid until
 * the next call on the same thread.
 */
STACKIMPORT_API size_t STACKIMPORT_CALL stackimport_snd_to_wav(
	const void* snd_data,
	size_t snd_size,
	void* wav_buffer,
	size_t wav_capacity,
	const char** out_error);

#ifdef __cplusplus
}
#endif

#endif
