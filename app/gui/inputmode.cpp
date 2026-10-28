#include "inputmode.h"

#include <QGuiApplication>
#include <QKeyEvent>

InputMode::InputMode(QObject* parent)
    : QObject(parent)
{
    qApp->installEventFilter(this);
}

bool InputMode::eventFilter(QObject* watched, QEvent* event)
{
    switch (event->type()) {
    case QEvent::KeyPress: {
        // Modifier-only presses (e.g. Alt+Tab away) aren't navigation
        auto key = static_cast<QKeyEvent*>(event)->key();
        if (key != Qt::Key_Alt && key != Qt::Key_Control && key != Qt::Key_Shift && key != Qt::Key_Meta) {
            setKeyboard(true);
        }
        break;
    }
    case QEvent::MouseButtonPress:
    case QEvent::TouchBegin:
    case QEvent::Wheel:
        setKeyboard(false);
        break;
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

void InputMode::setKeyboard(bool keyboard)
{
    if (keyboard != m_Keyboard) {
        m_Keyboard = keyboard;
        emit keyboardChanged();
    }
}
