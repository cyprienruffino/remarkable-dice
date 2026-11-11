// AppLoad backend for Dice & Life: keeps the frontend's state (players, life
// totals, recent rolls) saved, so a game survives closing the app.

#include "appload.h"
#include "pen_strokes.h"

#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include <poll.h>

// Must match ui/main.qml
constexpr int MSG_SAVE = 1;   // frontend -> backend: state as JSON
constexpr int MSG_STATE = 100; // backend -> frontend: saved state as JSON, "{}" if none
constexpr int MSG_STROKE = 101; // backend -> frontend: a pen stroke, {"eraser", "points": [x, y, ...]} in screen pixels

namespace {

std::filesystem::path statePath()
{
    const char *home = std::getenv("HOME");
    return std::filesystem::path(home ? home : ".") / ".local/share/dice/state.json";
}

std::string load()
{
    std::ifstream file(statePath());
    std::stringstream contents;
    contents << file.rdbuf();
    return file && !contents.str().empty() ? contents.str() : "{}";
}

void save(const std::string &state)
{
    std::error_code error;
    std::filesystem::create_directories(statePath().parent_path(), error);
    // Write then rename, so a crash can't leave a truncated file
    const std::filesystem::path temporary = statePath().string() + ".new";
    {
        std::ofstream file(temporary);
        file << state;
        if (!file) {
            std::cerr << "Failed to save " << temporary << std::endl;
            return;
        }
    }
    std::filesystem::rename(temporary, statePath(), error);
}

std::string strokeJson(const rmpen::Stroke &stroke)
{
    std::ostringstream json;
    json.setf(std::ios::fixed);
    json.precision(1);
    json << "{\"eraser\":" << (stroke.eraser ? "true" : "false") << ",\"points\":[";
    for (size_t i = 0; i < stroke.points.size(); i++) {
        json << (i ? "," : "") << stroke.points[i].x << ',' << stroke.points[i].y;
    }
    json << "]}";
    return json.str();
}

} // namespace

int main(int argc, char *argv[])
{
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <appload socket path>" << std::endl;
        return 1;
    }

    appload::Connection appload;
    if (!appload.connect(argv[1])) {
        perror("connect");
        return 1;
    }

    // Pen strokes for the notes page's native ink, which doesn't give them to the app
    rmpen::StrokeReader pen;
    pen.open();

    appload::Message message;
    while (true) {
        pollfd fds[2] = { { appload.fd(), POLLIN, 0 }, { pen.fd(), POLLIN, 0 } };
        if (poll(fds, pen.fd() == -1 ? 1 : 2, -1) < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (pen.fd() != -1 && (fds[1].revents & POLLIN)) {
            pen.read([&](const rmpen::Stroke &stroke) { appload.send(MSG_STROKE, strokeJson(stroke)); });
        }
        if (!(fds[0].revents & (POLLIN | POLLHUP | POLLERR))) {
            continue;
        }
        if (!appload.receive(&message)) {
            break;
        }
        switch (message.type) {
        case appload::MSG_TERMINATE:
            return 0;
        case appload::MSG_NEW_FRONTEND:
            appload.send(MSG_STATE, load());
            break;
        case MSG_SAVE:
            save(message.contents);
            break;
        default:
            std::cerr << "Unknown message type " << message.type << std::endl;
        }
    }
    return 0;
}
