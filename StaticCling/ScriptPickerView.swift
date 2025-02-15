import Defaults
import Lowtech
import SwiftUI
import System
import UniformTypeIdentifiers

struct ScriptPickerView: View {
    let fileURLs: [URL]
    @Environment(\.dismiss) var dismiss
    @State private var isShowingAddScript = false
    @State private var scriptName = ""
    @State private var selectedRunner: ScriptRunner? = .zsh
    @State private var scriptManager = SM

    func scriptButton(_ script: URL) -> some View {
        HStack {
            Button(action: {
                _ = shellProcOut(script.path, args: fileURLs.map(\.path), env: scriptManager.shellEnv)
                dismiss()
            }) {
                HStack {
                    Image(nsImage: icon(for: script))
                    Text(script.lastPathComponent.ns.deletingPathExtension)

                    if let shortcut = scriptManager.scriptShortcuts[script] {
                        Spacer()
                        Text(String(shortcut).uppercased()).monospaced().bold().foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(FlatButton(color: .bg.primary.opacity(0.4), textColor: .primary))
            .ifLet(scriptManager.scriptShortcuts[script]) {
                $0.keyboardShortcut(KeyEquivalent($1), modifiers: [])
            }

            Button(action: {
                openInEditor(script)
            }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(FlatButton(color: .bg.primary.opacity(0.4), textColor: .primary))
        }
    }

    var scriptList: some View {
        ForEach(scriptManager.scriptURLs.filter(\.fileExists), id: \.path) { script in
            scriptButton(script)
        }.focusable(false)
    }

    var body: some View {
        VStack {
            if !scriptManager.scriptURLs.isEmpty {
                scriptList
            } else {
                Text("No scripts found in")
                Button("\(scriptsFolder.shellString)") {
                    NSWorkspace.shared.open(scriptsFolder.url)
                }
                .buttonStyle(TextButton())
                .font(.mono(10))
                .padding(.top, 2)
                .focusable(false)
            }

            HStack {
                Button("Create Script") { isShowingAddScript = true }
                Button("Open script folder") {
                    NSWorkspace.shared.open(scriptsFolder.url)
                    NSApp.deactivate()
                }
            }
            .padding(.top)
        }
        .padding()
        .sheet(isPresented: $isShowingAddScript, onDismiss: createNewScript) {
            AddScriptView(name: $scriptName, selectedRunner: $selectedRunner)
        }
    }

    func createNewScript() {
        guard !scriptName.isEmpty else { return }
        let ext = selectedRunner?.fileExtension ?? "sh"
        let newScript = scriptsFolder / "\(scriptName.safeFilename).\(ext)"

        do {
            let shebang = selectedRunner?.shebang ?? "#!/bin/zsh"
            try "\(shebang)\n".write(to: newScript.url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: newScript.string)
            newScript.edit()
        } catch {
            log.error("Failed to create script: \(error.localizedDescription)")
        }

        scriptName = ""
        selectedRunner = nil
        scriptManager.fetchScripts() // Update scripts and shortcuts
    }
}

func openInEditor(_ file: URL) {
    NSWorkspace.shared.open(
        [file],
        withApplicationAt: Defaults[.editorApp].fileURL ?? URL(fileURLWithPath: "/Applications/TextEdit.app"),
        configuration: NSWorkspace.OpenConfiguration()
    )

}

extension FilePath {
    func edit() {
        openInEditor(url)
    }
}

extension URL {
    var fileExists: Bool {
        filePath?.exists ?? false
    }
}

struct AddScriptView: View {
    @Binding var name: String
    @Binding var selectedRunner: ScriptRunner?

    var body: some View {
        VStack {
            VStack {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        dismiss()
                        NSApp.deactivate()
                    }
                Picker("Script runner", selection: $selectedRunner) {
                    ForEach(ScriptRunner.allCases, id: \.self) { runner in
                        Text("\(runner.name) (\(runner.path))").tag(runner as ScriptRunner?)
                    }
                    Divider()
                    Text("Custom").tag(nil as ScriptRunner?)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding()
            HStack {
                Button {
                    cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                Button {
                    dismiss()
                    NSApp.deactivate()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
            }
        }
        .onExitCommand {
            cancel()
        }
        .padding()
    }

    func cancel() {
        name = ""
        selectedRunner = nil
        dismiss()
    }

    @Environment(\.dismiss) private var dismiss
}

enum ScriptRunner: String, CaseIterable {
    case sh
    case zsh
    case fish
    case python3
    case ruby
    case perl
    case swift
    case osascript
    case node

    init?(fromShebang shebang: String) {
        let path = shebang.replacingOccurrences(of: "#!", with: "").replacingOccurrences(of: "/usr/bin/env ", with: "").trimmingCharacters(in: .whitespaces)
        guard let runner = ScriptRunner.allCases.first(where: { $0.path == path }) ?? ScriptRunner.allCases.first(where: { $0.path.contains(path) }) else {
            return nil
        }
        self = runner
    }

    init?(fromExtension ext: String) {
        guard let runner = ScriptRunner.allCases.first(where: { $0.fileExtension == ext }) else {
            return nil
        }
        self = runner
    }

    var fileExtension: String {
        switch self {
        case .sh: "sh"
        case .zsh: "zsh"
        case .fish: "fish"
        case .python3: "py"
        case .ruby: "rb"
        case .perl: "pl"
        case .swift: "swift"
        case .osascript: "scpt"
        case .node: "js"
        }
    }

    var shebang: String {
        "#!\(path)"
    }

    var utType: UTType? {
        if let utType = UTType(filenameExtension: fileExtension) {
            return utType
        }

        switch self {
        case .sh: return .shellScript
        case .zsh: return .shellScript
        case .fish: return .shellScript
        case .python3: return .pythonScript
        case .ruby: return .rubyScript
        case .perl: return .perlScript
        case .swift: return .swiftSource
        case .osascript: return .appleScript
        case .node: return .javaScript
        }
    }

    var name: String {
        switch self {
        case .sh: "Bash"
        case .zsh: "Zsh"
        case .fish: "Fish"
        case .python3: "Python 3"
        case .ruby: "Ruby"
        case .perl: "Perl"
        case .swift: "Swift"
        case .osascript: "AppleScript"
        case .node: "Node.js"
        }
    }

    var path: String {
        switch self {
        case .sh: "/bin/sh"
        case .zsh: "/bin/zsh"
        case .fish: "/usr/local/bin/fish"
        case .python3: "/usr/bin/python3"
        case .ruby: "/usr/bin/ruby"
        case .perl: "/usr/bin/perl"
        case .swift: "/usr/bin/swift"
        case .osascript: "/usr/bin/osascript"
        case .node: "/usr/local/bin/node"
        }
    }
}
