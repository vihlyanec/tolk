import SwiftUI

struct ShortcutSettingsView: View {
    @Binding var shifted: Bool
    let status: String

    var body: some View {
        Form {
            Section("Из любого приложения") {
                let prefix = shifted ? "⌃⇧" : "⌃"
                shortcut("Быстро добавить задачу", prefix + "Q")
                shortcut("Открыть новую заметку-стикер", prefix + "D")
                Toggle("Всегда использовать варианты с Shift", isOn: $shifted)
                if !status.isEmpty {
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("Если основное сочетание занято, Толк пробует вариант с Shift.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Заметки и задачи") {
                shortcut("Создать задачу из текста до курсора", "⇧⌘↩")
                shortcut("Быстрые действия выбранной задачи", "⇧⌘K")
                shortcut("Открыть быстрый ввод", "⌘N")
                shortcut("Создать заметку-стикер", "⌘D")
                shortcut("Открыть проект или карточку очереди в фокусе", "↩")
            }
            Section("Быстрый ввод и формы") {
                shortcut("Применить подсказку или сохранить задачу", "↩")
                shortcut("Открыть описание из названия", "⇧↩")
                shortcut("Сохранить из описания или полной формы", "⌘↩")
                shortcut("Подставить подсказку", "⇥")
                shortcut("Следующее или предыдущее поле полной формы", "⇥ / ⇧⇥")
                shortcut("Выбрать подсказку или быстрое действие", "↑ / ↓")
                shortcut("Снять распознавание команды при удалении", "⌫ / ⌦")
                shortcut("Отменить ввод или закрыть быстрые действия", "Esc")
            }
            Section("Календарь и диалоги") {
                shortcut("Выбрать день в мини-календаре", "← ↑ ↓ →")
                shortcut("Перейти к выбранной дате", "↩")
                shortcut("Подтвердить выбранное действие в диалоге", "↩")
                shortcut("Закрыть меню «Сегодня» или пропустить заметку паузы", "Esc")
            }
            Section("Приложение и редактирование") {
                shortcut("Главное окно", "⌘0")
                shortcut("Настройки", "⌘,")
                shortcut("Завершить Толк", "⌘Q")
                shortcut("Отменить изменение записи", "⌘Z")
                shortcut("Повторить изменение записи", "⇧⌘Z")
                shortcut("Вырезать", "⌘X")
                shortcut("Копировать", "⌘C")
                shortcut("Вставить", "⌘V")
                shortcut("Выделить всё", "⌘A")
            }
        }.formStyle(.grouped).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
        }.accessibilityElement(children: .combine)
    }
}
