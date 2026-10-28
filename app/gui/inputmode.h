#pragma once

#include <QObject>

// Stand-In: whether the user is driving the UI with keys or a gamepad (focus rings
// show) or with a mouse or touch (they don't). Gamepad navigation arrives as key events.
class InputMode : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool keyboard READ keyboard NOTIFY keyboardChanged)

public:
    explicit InputMode(QObject* parent = nullptr);

    bool keyboard() const { return m_Keyboard; }

signals:
    void keyboardChanged();

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    void setKeyboard(bool keyboard);

    bool m_Keyboard = false;
};
