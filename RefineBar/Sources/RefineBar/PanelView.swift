import SwiftUI

struct PanelView: View {
    @ObservedObject var model: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.showSettings {
                SettingsView(model: model)
            } else {
                recordRow
                draftBox
                Picker("Style", selection: $model.style) {
                    ForEach(ViewModel.styles) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                resultBox
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 4)
        .frame(width: 400)
    }

    private var header: some View {
        HStack {
            Text(model.showSettings ? "Settings" : "Say it in English")
                .font(.headline)
            Spacer()
            if !model.showSettings && (!model.draft.isEmpty || !model.result.isEmpty) {
                Button("Clear", action: model.clear)
                    .buttonStyle(.borderless)
                    .help("Clear the draft and result")
            }
            Button {
                model.showSettings.toggle()
            } label: {
                Image(systemName: model.showSettings ? "xmark.circle" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help(model.showSettings ? "Close settings" : "Settings")
        }
    }

    private var recordRow: some View {
        HStack(spacing: 12) {
            Button(action: model.toggleRecording) {
                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(model.isRecording ? Color.red : Color.accentColor))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help(model.isRecording ? "Stop and refine (⌘R)" : "Record (⌘R)")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if model.isBusy { ProgressView().controlSize(.small) }
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if model.isRecording {
                    LevelBar(level: model.level)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var statusText: String {
        if model.isRecording {
            let seconds = Int(model.elapsed)
            return String(format: "Listening… %d:%02d", seconds / 60, seconds % 60)
        }
        if !model.status.isEmpty { return model.status }
        return "Speak, or type below. Broken English or Bahasa is fine."
    }

    private var draftBox: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 64, maxHeight: 120)
            if model.draft.isEmpty {
                Text("Type it. Add /* for a note only Refine sees, like /*udah selesai")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
    }

    @ViewBuilder
    private var resultBox: some View {
        if !model.result.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.result)
                    .font(.system(size: 20, weight: .medium))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(model.isBusy ? 0.5 : 1)
                HStack {
                    Spacer()
                    Button(model.copied ? "Copied" : "Copy", action: model.copyResult)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .help("Copy the result (⇧⌘C)")
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
        }
    }
}

private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                // Speech RMS is usually 0.01-0.3; a square root spreads that out.
                Capsule().fill(Color.red.opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(min(1, sqrt(level) * 1.6)))
            }
        }
        .frame(height: 5)
        .animation(.linear(duration: 0.1), value: level)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ViewModel
    @State private var keyInput = ""
    @State private var keyMessage: String?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Groq API key").font(.subheadline.weight(.semibold))
                HStack {
                    SecureField(model.hasAPIKey ? "Saved. Paste a new key to replace it" : "gsk_…", text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(keyMessage ?? "From console.groq.com. Stored in your Mac's keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Never send these words").font(.subheadline.weight(.semibold))
                TextField("Client or project code names, comma-separated", text: $model.hiddenTerms)
                    .textFieldStyle(.roundedBorder)
                Text("Hidden before sending, like links, emails, keys and numbers. Your voice recording itself is sent to Groq as-is, since sound can't be redacted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(!LoginItem.isInstalledLocation)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.secondary)
                } else if !LoginItem.isInstalledLocation {
                    Text("Available once installed with build.sh --install.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if LoginItem.needsApproval {
                    Button("Approve in System Settings…", action: LoginItem.openSystemSettings)
                        .buttonStyle(.link).font(.caption)
                }
            }

            HStack {
                Spacer()
                Button("Quit RefineBar") { NSApp.terminate(nil) }
            }
        }
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if model.saveAPIKey(key) {
            keyInput = ""
            keyMessage = "Saved."
        } else {
            keyMessage = "Couldn't save to the keychain."
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginMessage = nil
        } catch {
            loginMessage = error.localizedDescription
        }
        launchAtLogin = LoginItem.isEnabled
    }
}
