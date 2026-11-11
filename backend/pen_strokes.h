// Records pen strokes from the tablet's digitizer, in screen pixels, for AppLoad
// backends. xochitl's native ink (NativeInk.qml) draws strokes as they're
// written but doesn't hand their points to apps, so the backend reads them
// from the digitizer too; several readers can share an input device.
//
//   rmpen::StrokeReader pen;
//   pen.open();                      // poll(pen.fd()) alongside AppLoad's socket
//   pen.read([](const rmpen::Stroke &stroke) { ... });
//
// The digitizer maps straight to the screen on the Paper Pro Move: screen
// pixel = raw value * screen size / axis maximum.
#ifndef RMPEN_PEN_STROKES_H
#define RMPEN_PEN_STROKES_H

#include <cerrno>
#include <climits>
#include <cstdio>
#include <string>
#include <vector>

#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace rmpen {

struct Point
{
    float x;
    float y;
    float pressure; // 0 to 1
};

struct Stroke
{
    std::vector<Point> points;
    bool eraser = false; // written with the eraser end of the pen
};

class StrokeReader
{
public:
    ~StrokeReader()
    {
        if (m_fd != -1) {
            close(m_fd);
        }
    }

    // Finds the digitizer: the input device with a pen tool and absolute axes.
    // The screen size defaults to the Paper Pro Move's.
    bool open(int screenWidth = 954, int screenHeight = 1696)
    {
        m_screenWidth = screenWidth;
        m_screenHeight = screenHeight;
        for (int i = 0; i < 32; i++) {
            const std::string path = "/dev/input/event" + std::to_string(i);
            const int fd = ::open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
            if (fd == -1) {
                continue;
            }
            if (hasBit(fd, EV_KEY, BTN_TOOL_PEN, KEY_MAX) && hasBit(fd, EV_ABS, ABS_X, ABS_MAX)
                && ioctl(fd, EVIOCGABS(ABS_X), &m_x) == 0 && ioctl(fd, EVIOCGABS(ABS_Y), &m_y) == 0) {
                if (ioctl(fd, EVIOCGABS(ABS_PRESSURE), &m_pressure) != 0) {
                    m_pressure = {};
                }
                m_fd = fd;
                return true;
            }
            close(fd);
        }
        return false;
    }

    int fd() const { return m_fd; }

    // Reads pending events, calling onStroke for each stroke finished. Returns
    // false once the device is gone.
    template <typename OnStroke>
    bool read(OnStroke onStroke)
    {
        input_event events[64];
        while (true) {
            const ssize_t n = ::read(m_fd, events, sizeof events);
            if (n < 0 && errno == EAGAIN) {
                return true;
            }
            if (n <= 0) {
                return false;
            }
            for (size_t i = 0; i < size_t(n) / sizeof(input_event); i++) {
                handle(events[i], onStroke);
            }
        }
    }

    // Uses the given axes instead of a device, for replaying recorded events
    // through feed(), e.g. in tests
    void setAxes(input_absinfo x, input_absinfo y, input_absinfo pressure, int screenWidth = 954, int screenHeight = 1696)
    {
        m_x = x;
        m_y = y;
        m_pressure = pressure;
        m_screenWidth = screenWidth;
        m_screenHeight = screenHeight;
    }

    template <typename OnStroke>
    void feed(const input_event &event, OnStroke onStroke)
    {
        handle(event, onStroke);
    }

private:
    static bool hasBit(int fd, int type, int bit, int max)
    {
        std::vector<unsigned long> bits(max / (sizeof(long) * CHAR_BIT) + 1);
        if (ioctl(fd, EVIOCGBIT(type, bits.size() * sizeof(long)), bits.data()) < 0) {
            return false;
        }
        return bits[bit / (sizeof(long) * CHAR_BIT)] & (1UL << (bit % (sizeof(long) * CHAR_BIT)));
    }

    static float scale(int value, const input_absinfo &axis, int size)
    {
        const int range = axis.maximum - axis.minimum;
        return range > 0 ? float(value - axis.minimum) * size / range : 0;
    }

    template <typename OnStroke>
    void handle(const input_event &event, OnStroke &onStroke)
    {
        switch (event.type) {
        case EV_ABS:
            if (event.code == ABS_X) {
                m_rawX = event.value;
            } else if (event.code == ABS_Y) {
                m_rawY = event.value;
            } else if (event.code == ABS_PRESSURE) {
                m_rawPressure = event.value;
            }
            break;
        case EV_KEY:
            if (event.code == BTN_TOOL_RUBBER) {
                m_eraser = event.value != 0;
            } else if (event.code == BTN_TOOL_PEN && event.value) {
                m_eraser = false;
            } else if (event.code == BTN_TOUCH) {
                if (event.value) {
                    m_stroke = Stroke();
                    m_stroke.eraser = m_eraser;
                    m_touching = true;
                } else if (m_touching) {
                    m_touching = false;
                    if (!m_stroke.points.empty()) {
                        onStroke(m_stroke);
                    }
                }
            }
            break;
        case EV_SYN:
            if (event.code == SYN_REPORT && m_touching) {
                const float pressureRange = float(m_pressure.maximum - m_pressure.minimum);
                m_stroke.points.push_back({
                    scale(m_rawX, m_x, m_screenWidth),
                    scale(m_rawY, m_y, m_screenHeight),
                    pressureRange > 0 ? (m_rawPressure - m_pressure.minimum) / pressureRange : 1.0f,
                });
            }
            break;
        }
    }

    int m_fd = -1;
    int m_screenWidth = 954;
    int m_screenHeight = 1696;
    input_absinfo m_x = {};
    input_absinfo m_y = {};
    input_absinfo m_pressure = {};
    int m_rawX = 0;
    int m_rawY = 0;
    int m_rawPressure = 0;
    bool m_eraser = false;
    bool m_touching = false;
    Stroke m_stroke;
};

} // namespace rmpen

#endif
