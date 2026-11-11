// AppLoad backend for Dice & Life: keeps the frontend's state (players, life
// totals, recent rolls) saved, so a game survives closing the app.

#include "appload.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

// Must match ui/main.qml
constexpr int MSG_SAVE = 1;   // frontend -> backend: state as JSON
constexpr int MSG_STATE = 100; // backend -> frontend: saved state as JSON, "{}" if none

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

    appload::Message message;
    while (appload.receive(&message)) {
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
