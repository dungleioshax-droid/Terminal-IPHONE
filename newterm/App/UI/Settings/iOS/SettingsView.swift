//
//  SettingsView.swift
//  NewTerm (iOS)
//
//  Created by Adam Demasi on 3/4/21.
//

import SwiftUI
import CoreHaptics
import NewTermCommon

fileprivate extension KeyboardArrowsStyle {
	var name: String {
		switch self {
		case .butterfly:   return "Butterfly"
		case .scissor:     return "Scissor"
		case .classic:     return "Classic"
		case .vim:         return "Vim"
		case .vimInverted: return "Vim Inverted"
		}
	}
}

fileprivate extension KeyboardTrackpadSensitivity {
	var name: String {
		switch self {
		case .off:    return "Off"
		case .low:    return "Low"
		case .medium: return "Medium"
		case .high:   return "High"
		}
	}
}

struct SettingsView: View {

	@Environment(\.presentationMode)
	var presentationMode

	@ObservedObject var preferences = Preferences.shared

	var windowScene: UIWindowScene?

	@State private var keyboardToolbarState = KeyboardToolbarViewState()

	private func dismiss() {
		if let windowScene = windowScene {
			UIApplication.shared.requestSceneSessionDestruction(windowScene.session, options: nil, errorHandler: nil)
		} else {
			// TODO: presentationMode seems useless when UIKit is presenting
			// the view controller rather than SwiftUI? Ugh
//			presentationMode.wrappedValue.dismiss()
			NotificationCenter.default.post(name: RootViewController.settingsViewDoneNotification, object: nil)
		}
	}

	var body: some View {
		let list = List() {
			PreferencesGroup(header: Text("Terminal")) {
				NavigationLink(destination: SettingsFontView(),
											 label: { KeyValueView(title: Text("Font"),
																						 value: Text("\(preferences.fontName), \(Int(preferences.fontSize))")) })

				NavigationLink(destination: SettingsThemeView(),
											 label: { KeyValueView(title: Text("Theme"),
																						 value: Text(preferences.themeName)) })
			}

			PreferencesGroup(header: Text("Keyboard"),
											 footer: Text("Touch and hold the Space bar, then drag around the keyboard to move the cursor.")) {
				PreferencesPicker(selection: preferences.$keyboardArrowsStyle,
													label: Text("Arrow Keys"),
													valueLabel: Text(preferences.keyboardArrowsStyle.name),
													asLink: true) {
					ForEach(KeyboardArrowsStyle.allCases, id: \.self) { key in
						HStack(alignment: .center) {
							Text(key.name)
							Spacer()
							KeyboardToolbarKeyStack(toolbar: .padPrimaryTrailing,
																			arrowsStyle: key)
								.environmentObject(keyboardToolbarState)
								.disabled(true)
						}
							.height(44)
					}
				}

				PreferencesPicker(selection: preferences.$keyboardTrackpadSensitivity,
													label: Text("Trackpad Sensitivity"),
													valueLabel: Text(preferences.keyboardTrackpadSensitivity.name),
													asStepper: true)
			}

			PreferencesGroup(header: Text("Bell"),
											 footer: Text("When a terminal application needs to notify you of something, it rings the bell.")) {
				Toggle("Make beep sound", isOn: preferences.$bellSound)
				if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
					Toggle("Make haptic vibration", isOn: preferences.$bellVibrate)
				}
				Toggle("Show heads-up display", isOn: preferences.$bellHUD)
			}

			PreferencesGroup(header: Text("AI CLI")) {
				NavigationLink(destination: SettingsAICLIView(),
											 label: { Text("Claude Code Environment") })
			}

			PreferencesGroup {
				NavigationLink(destination: SettingsAdvancedView(),
											 label: { Text("Advanced") })
			}

			PreferencesGroup {
				NavigationLink(destination: SettingsAboutView(),
											 label: { Text("About") })
			}
		}
			.listStyle(InsetGroupedListStyle())
			.onChange(of: [preferences.bellVibrate, preferences.bellSound]) { _ in
				HapticController.playBell()
			}

		return NavigationView {
			list
				.navigationBarTitle("SETTINGS", displayMode: .large)
				.navigationBarItems(trailing: Button(action: { self.dismiss() },
																						 label: { Text(verbatim: .done).bold() }))
		}
			.navigationViewStyle(StackNavigationViewStyle())
	}
}

struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		SettingsView()
	}
}

// MARK: - AI CLI

/// Status and repair tools for the bundled AI CLI environment (Node.js,
/// npm and Claude Code helpers shipped inside the NewTerm 3 AI package).
struct SettingsAICLIView: View {

	@State private var statusText = "Checking…"
	@State private var outputText = ""
	@State private var running = false

	var body: some View {
		List() {
			Section(header: Text("Status"),
							footer: Text("NewTerm 3 AI ships its own Node.js runtime — nothing needs to be installed from a repo. Use the actions below to check, install or repair it.")) {
				HStack(alignment: .firstTextBaseline) {
					if running {
						ProgressView()
							.padding(.trailing, 6)
					}
					Text(statusText)
				}
			}

			Section(header: Text("Actions")) {
				Button(action: { self.run("doctor") },
							 label: { Label("Environment check (aienv doctor)", systemImage: "checkmark.circle") })
				Button(action: { self.run("install-claude") },
							 label: { Label("Install / Repair Claude Code", systemImage: "arrow.down.circle") })
				Button(action: { self.run("fix-node") },
							 label: { Label("Reinstall / Re-sign Node.js", systemImage: "arrow.clockwise") })
			}
				.disabled(running || !AIEnv.available)
				.opacity(AIEnv.available ? 1 : 0.5)

			if !AIEnv.available {
				PreferencesGroup {
					Text("The aienv helpers were not found. Make sure the “NewTerm 3 AI” package is installed, then reopen this screen.")
				}
			}

			if !outputText.isEmpty {
				Section(header: Text("Output")) {
					Text(outputText)
						.font(.system(.caption, design: .monospaced))
				}
			}
		}
			.listStyle(InsetGroupedListStyle())
			.navigationBarTitle(Text("AI CLI"), displayMode: .inline)
			.onAppear { self.refresh() }
	}

	private func refresh() {
		if !AIEnv.available {
			statusText = "Not installed"
			return
		}
		statusText = AIEnv.statusSummary()
	}

	private func run(_ command: String) {
		running = true
		outputText = "Running: aienv \(command) …"
		AIEnv.run(command) { exitCode, output in
			DispatchQueue.main.async {
				self.running = false
				var text = "$ aienv \(command)\n\n" + output
				if exitCode != 0 {
					text += "\n(exit code \(exitCode))"
				}
				self.outputText = text
				self.refresh()
			}
		}
	}

}
