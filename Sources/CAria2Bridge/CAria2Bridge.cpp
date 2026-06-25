#include "CAria2Bridge.h"

#include <aria2/aria2.h>

#include <memory>
#include <string>
#include <utility>
#include <vector>

struct swift_aria2_session {
    aria2::Session *raw;
};

namespace {

swift_aria2_download_state_t mapStatus(aria2::DownloadStatus status) {
    switch (status) {
    case aria2::DOWNLOAD_ACTIVE:
        return SWIFT_ARIA2_DOWNLOAD_STATE_ACTIVE;
    case aria2::DOWNLOAD_WAITING:
        return SWIFT_ARIA2_DOWNLOAD_STATE_WAITING;
    case aria2::DOWNLOAD_PAUSED:
        return SWIFT_ARIA2_DOWNLOAD_STATE_PAUSED;
    case aria2::DOWNLOAD_COMPLETE:
        return SWIFT_ARIA2_DOWNLOAD_STATE_COMPLETE;
    case aria2::DOWNLOAD_ERROR:
        return SWIFT_ARIA2_DOWNLOAD_STATE_ERROR;
    case aria2::DOWNLOAD_REMOVED:
        return SWIFT_ARIA2_DOWNLOAD_STATE_REMOVED;
    }

    return SWIFT_ARIA2_DOWNLOAD_STATE_UNKNOWN;
}

aria2::KeyVals makeOptions(
    const char *directory,
    const char *fileName,
    int connectionsPerServer,
    int splitCount
) {
    aria2::KeyVals options;
    options.emplace_back("dir", directory == nullptr ? "" : directory);
    options.emplace_back("out", fileName == nullptr ? "" : fileName);
    options.emplace_back("max-connection-per-server", std::to_string(connectionsPerServer));
    options.emplace_back("split", std::to_string(splitCount));
    return options;
}

} // namespace

int swift_aria2_backend_available(void) {
    return 1;
}

const char *swift_aria2_backend_status_message(void) {
    return "SwiftAria native libaria2 backend is linked.";
}

swift_aria2_session_t *swift_aria2_session_create(void) {
    if (aria2::libraryInit() < 0) {
        return nullptr;
    }

    aria2::SessionConfig config;
    config.keepRunning = true;
    config.useSignalHandler = false;

    aria2::KeyVals options;
    options.emplace_back("enable-color", "false");
    options.emplace_back("summary-interval", "0");

    aria2::Session *raw = aria2::sessionNew(options, config);
    if (raw == nullptr) {
        aria2::libraryDeinit();
        return nullptr;
    }

    auto *session = new swift_aria2_session;
    session->raw = raw;
    return session;
}

void swift_aria2_session_destroy(swift_aria2_session_t *session) {
    if (session == nullptr) {
        return;
    }

    if (session->raw != nullptr) {
        aria2::shutdown(session->raw, true);
        while (aria2::run(session->raw, aria2::RUN_ONCE) > 0) {
        }
        aria2::sessionFinal(session->raw);
    }

    aria2::libraryDeinit();
    delete session;
}

int swift_aria2_session_run_once(swift_aria2_session_t *session) {
    if (session == nullptr || session->raw == nullptr) {
        return -1;
    }

    return aria2::run(session->raw, aria2::RUN_ONCE);
}

int swift_aria2_session_shutdown(swift_aria2_session_t *session) {
    if (session == nullptr || session->raw == nullptr) {
        return -1;
    }

    return aria2::shutdown(session->raw, true);
}

int swift_aria2_add_uri(
    swift_aria2_session_t *session,
    const char *url,
    const char *directory,
    const char *file_name,
    int connections_per_server,
    int split_count,
    uint64_t *gid
) {
    if (session == nullptr || session->raw == nullptr || url == nullptr || gid == nullptr) {
        return -1;
    }

    std::vector<std::string> uris;
    uris.emplace_back(url);

    aria2::A2Gid ariaGid = 0;
    aria2::KeyVals options = makeOptions(directory, file_name, connections_per_server, split_count);
    int result = aria2::addUri(session->raw, &ariaGid, uris, options);
    if (result == 0) {
        *gid = ariaGid;
    }

    return result;
}

int swift_aria2_pause(swift_aria2_session_t *session, uint64_t gid) {
    if (session == nullptr || session->raw == nullptr) {
        return -1;
    }

    return aria2::pauseDownload(session->raw, gid, true);
}

int swift_aria2_resume(swift_aria2_session_t *session, uint64_t gid) {
    if (session == nullptr || session->raw == nullptr) {
        return -1;
    }

    return aria2::unpauseDownload(session->raw, gid);
}

int swift_aria2_cancel(swift_aria2_session_t *session, uint64_t gid) {
    if (session == nullptr || session->raw == nullptr) {
        return -1;
    }

    return aria2::removeDownload(session->raw, gid, true);
}

int swift_aria2_get_status(
    swift_aria2_session_t *session,
    uint64_t gid,
    swift_aria2_download_status_t *status
) {
    if (session == nullptr || session->raw == nullptr || status == nullptr) {
        return -1;
    }

    aria2::DownloadHandle *handle = aria2::getDownloadHandle(session->raw, gid);
    if (handle == nullptr) {
        return -2;
    }

    status->gid = gid;
    status->state = mapStatus(handle->getStatus());
    status->completed_length = handle->getCompletedLength();
    status->total_length = handle->getTotalLength();
    status->download_speed = handle->getDownloadSpeed();
    status->error_code = handle->getErrorCode();

    aria2::deleteDownloadHandle(handle);
    return 0;
}
