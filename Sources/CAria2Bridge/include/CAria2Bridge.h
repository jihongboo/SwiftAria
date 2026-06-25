#ifndef CAria2Bridge_h
#define CAria2Bridge_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct swift_aria2_session swift_aria2_session_t;

typedef enum swift_aria2_download_state {
    SWIFT_ARIA2_DOWNLOAD_STATE_UNKNOWN = 0,
    SWIFT_ARIA2_DOWNLOAD_STATE_ACTIVE = 1,
    SWIFT_ARIA2_DOWNLOAD_STATE_WAITING = 2,
    SWIFT_ARIA2_DOWNLOAD_STATE_PAUSED = 3,
    SWIFT_ARIA2_DOWNLOAD_STATE_COMPLETE = 4,
    SWIFT_ARIA2_DOWNLOAD_STATE_ERROR = 5,
    SWIFT_ARIA2_DOWNLOAD_STATE_REMOVED = 6
} swift_aria2_download_state_t;

typedef struct swift_aria2_download_status {
    uint64_t gid;
    swift_aria2_download_state_t state;
    int64_t completed_length;
    int64_t total_length;
    int64_t download_speed;
    int error_code;
} swift_aria2_download_status_t;

int swift_aria2_backend_available(void);
const char *swift_aria2_backend_status_message(void);

swift_aria2_session_t *swift_aria2_session_create(void);
void swift_aria2_session_destroy(swift_aria2_session_t *session);
int swift_aria2_session_run_once(swift_aria2_session_t *session);
int swift_aria2_session_shutdown(swift_aria2_session_t *session);

int swift_aria2_add_uri(
    swift_aria2_session_t *session,
    const char *url,
    const char *directory,
    const char *file_name,
    int connections_per_server,
    int split_count,
    uint64_t *gid
);

int swift_aria2_pause(swift_aria2_session_t *session, uint64_t gid);
int swift_aria2_resume(swift_aria2_session_t *session, uint64_t gid);
int swift_aria2_cancel(swift_aria2_session_t *session, uint64_t gid);
int swift_aria2_get_status(
    swift_aria2_session_t *session,
    uint64_t gid,
    swift_aria2_download_status_t *status
);

#ifdef __cplusplus
}
#endif

#endif
