//
//  SubProcess.swift
//  NewTerm
//
//  Created by Adam Demasi on 9/1/18.
//  Copyright © 2018 HASHBANG Productions. All rights reserved.
//

import Foundation
import os.log

enum SubProcessIllegalStateError: Error, LocalizedError {
	case alreadyStarted, notStarted
	case openPtyFailed(errno: errno_t)
	case loginTtyFailed(errno: errno_t)
	case forkFailed(errno: errno_t)
	case deallocatedWhileRunning

	private func errorString(errno: errno_t) -> String {
		if let string = strerror(errno) {
			return String(cString: string)
		}
		return String(format: .localize("Unknown (%i)"), errno)
	}

	var errorDescription: String? {
		switch self {
		case .alreadyStarted, .notStarted, .deallocatedWhileRunning:
			return .localize("Internal state error")

		case .openPtyFailed(let errno):
			return String(format: .localize("Couldn’t initialize a terminal. %@"), errorString(errno: errno))

		case .loginTtyFailed(let errno):
			return String(format: .localize("Couldn’t prepare terminal for logging in. %@"), errorString(errno: errno))

		case .forkFailed(let errno):
			return String(format: .localize("Couldn’t start a terminal process. %@"), errorString(errno: errno))
		}
	}
}

enum SubProcessIOError: Error {
	case readFailed(errno: errno_t?)
	case writeFailed(errno: errno_t?)
}

protocol SubProcessDelegate: AnyObject {
	func subProcessDidConnect()
	func subProcess(didReceiveData data: [UTF8Char])
	func subProcess(didDisconnectWithError error: Error?)
	func subProcess(didReceiveError error: Error)
}

class SubProcess {

	private static let loginHelper: String? = Bundle.main.path(forAuxiliaryExecutable: "NewTermLoginHelper")

	/// The jailbreak root, derived from the app bundle itself (`<root>/Applications/NewTerm.app`).
	/// Classic rootless jailbreaks use `/var/jb`, but roothide bootstraps install into a
	/// randomised directory with no `/var/jb` symlink, so probing our own bundle path is the
	/// only reliable way to find the bootstrap’s tools (`login`, `zsh`, …) there.
	private static let jailbreakRoot: String = {
		#if targetEnvironment(simulator)
		return ""
		#else
		guard let executablePath = Bundle.main.executablePath, !executablePath.isEmpty else {
			return ""
		}
		let appDirectory = (executablePath as NSString).deletingLastPathComponent
		let applicationsDirectory = (appDirectory as NSString).deletingLastPathComponent
		guard (applicationsDirectory as NSString).lastPathComponent == "Applications",
					applicationsDirectory.count > "/Applications".count else {
			return ""
		}
		return applicationsDirectory
		#endif
	}()

	/// roothide bootstraps live under `/var/containers/Bundle/Application/.jbroot-<random>`;
	/// scan for them so the shell can still be found if the bundle-derived root is unusable.
	private static let roothideRoots: [String] = {
		let applicationsDirectory = "/var/containers/Bundle/Application"
		guard let entries = try? FileManager.default.contentsOfDirectory(atPath: applicationsDirectory) else {
			return []
		}
		return entries
			.filter { $0.hasPrefix(".jbroot-") }
			.sorted()
			.map { applicationsDirectory + "/" + $0 }
	}()

	/// Candidate jailbreak prefixes, most specific first. An empty string means the system root.
	private static let jailbreakRoots: [String] = {
		var roots: [String] = []
		func add(_ root: String) {
			if !roots.contains(root) {
				roots.append(root)
			}
		}
		if !jailbreakRoot.isEmpty {
			add(jailbreakRoot)
		}
		for root in roothideRoots {
			add(root)
		}
		if jailbreakRoot != "/var/jb" {
			add("/var/jb")
		}
		add("")
		return roots
	}()

	/// Finds the first executable among `<root>/<subPath>` for each candidate root.
	private static func findTool(_ subPaths: [String]) -> String? {
		for root in jailbreakRoots {
			for subPath in subPaths {
				let path = root.isEmpty ? "/\(subPath)" : "\(root)/\(subPath)"
				if access(path, X_OK) == 0 {
					return path
				}
			}
		}
		return nil
	}

	// TODO: Temporary workaround for XinaA15
	private static let isXina: Bool = (try? URL(fileURLWithPath: "/var/Liy/xina").checkResourceIsReachable()) == true

	/// roothide bootstraps live in a randomised root and hide it behind the `DYLD_*`
	/// environment injected into apps; `login(1)` strips that environment, so the
	/// login → helper → shell chain cannot start a bootstrap shell there. Detected by our
	/// bundle living somewhere other than the classic `/var/jb`.
	private static let isRoothide: Bool = !jailbreakRoot.isEmpty && jailbreakRoot != "/var/jb"

	private static let loginPath: String? = {
		#if targetEnvironment(macCatalyst)
		return "/usr/bin/login"
		#else
		return findTool(["usr/bin/login", "bin/login"])
		#endif
	}()

	/// How the terminal process is launched.
	private enum LaunchStrategy {
		case login, helper, shell
	}

	private static let launchStrategy: LaunchStrategy = {
		#if targetEnvironment(simulator)
		return .shell
		#elseif targetEnvironment(macCatalyst)
		return .login
		#else
		if isXina {
			return .shell
		}
		if isRoothide {
			// Skip login(1): it would sanitise away the environment bootstrap shells need.
			return loginHelper == nil ? .shell : .helper
		}
		if loginPath != nil, loginHelper != nil {
			return .login
		}
		// No login(1) anywhere: run the helper (it still sets up the tty properly) or the shell.
		return loginHelper == nil ? .shell : .helper
		#endif
	}()

	/// The user’s shell, resolved against the jailbreak prefixes like the bootstrap expects
	/// (`<root>/bin/zsh`, …), then the passwd shell, and finally `/bin/sh`, which every iOS ships.
	private static let resolvedShellPath: String = {
		if let shell = findTool(["bin/zsh", "usr/bin/zsh", "bin/bash", "usr/bin/bash", "bin/dash", "usr/bin/dash", "bin/sh", "usr/bin/sh"]) {
			return shell
		}
		if let passwdShell = userPasswd?.pw_shell {
			let path = String(cString: passwdShell)
			if access(path, X_OK) == 0 {
				return path
			}
		}
		return "/bin/sh"
	}()

	/// PATH for directly-launched shells: the jailbreak’s real (unmapped) directories first,
	/// the system last — the same strategy as the standalone Terminal app, which is proven to
	/// work on roothide bootstraps.
	private static func defaultPath() -> String {
		var parts: [String] = []
		var seen = Set<String>()
		func add(_ path: String) {
			if !path.isEmpty && !seen.contains(path) {
				seen.insert(path)
				parts.append(path)
			}
		}
		let standard = ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
		if !jailbreakRoot.isEmpty {
			for directory in standard { add(jailbreakRoot + directory) }
		}
		add(NSHomeDirectory() + "/.local/bin")
		for directory in standard { add(directory) }
		return parts.joined(separator: ":")
	}

	/// Human-readable probe results when no shell could be found, written into the
	/// terminal so an on-device screenshot explains the failure.
	static var shellResolutionDiagnostics: String? {
		guard resolvedShellPath == "/bin/sh" else {
			return nil
		}
		var passwdShell = "(none)"
		if let shell = userPasswd?.pw_shell {
			passwdShell = String(cString: shell)
		}
		let probedRoots = jailbreakRoots.map { $0.isEmpty ? "/" : $0 }.joined(separator: " ")
		var message = "\r\n\u{1b}[0;33m[NewTerm] No shell was found in the jailbreak — falling back to /bin/sh, which does not exist on iOS.\u{1b}[m\r\n"
		message += "[NewTerm] probed roots: \(probedRoots)\r\n"
		message += "[NewTerm] executable: \(Bundle.main.executablePath ?? "(unknown)")\r\n"
		message += "[NewTerm] passwd shell: \(passwdShell)\r\n"
		return message
	}

	private static var loginArgv: [String] {
		// Interestingly, despite what login(1) seems to imply, it still seems we need to manually
		// handle passing the -q (force hush login) flag. iTerm2 does this, so I guess it’s fine?
		let hushLoginURL = URL(fileURLWithPath: homeDirectory)/".hushlogin"
		let hushLogin = (try? hushLoginURL.checkResourceIsReachable()) == true
		return ["login", "-fp\(hushLogin ? "q" : "")", NSUserName(), loginHelper ?? ""]
	}

	private static let baseEnvp: [String] = [
		"TERM=xterm-256color",
		"COLORTERM=truecolor",
		"TERM_PROGRAM=NewTerm",
		"LC_TERMINAL=NewTerm"
	]

	private static var userPasswd: passwd? {
		let length = sysconf(_SC_GETPW_R_SIZE_MAX)
		let buffer = malloc(length)
		defer { buffer?.deallocate() }

		var pwd = passwd()
		var result: UnsafeMutablePointer<passwd>? = UnsafeMutablePointer<passwd>.allocate(capacity: 1)
		guard ie_getpwuid_r(getuid(), &pwd, buffer, length, &result) == 0 else {
			return nil
		}
		return pwd
	}

	private static var homeDirectory: String {
		if let result = userPasswd?.pw_dir {
			return String(cString: result)
		}
		return NSHomeDirectory()
	}

	weak var delegate: SubProcessDelegate?

	private var childPID: pid_t?
	private var fileDescriptor: Int32?

	private let queue = DispatchQueue(label: "ws.hbang.Terminal.io-queue")
	private var readSource: DispatchSourceRead?
	private var signalSource: DispatchSourceProcess?

	private let logger = Logger(subsystem: "ws.hbang.Terminal", category: "SubProcess")

	var screenSize = ScreenSize.default {
		didSet { updateWindowSize() }
	}

	func start(initialDirectory: String? = nil) throws {
		if childPID != nil {
			throw SubProcessIllegalStateError.alreadyStarted
		}

		// Initialise the pty
		var windowSize = screenSize.windowSize
		var fds = (primary: Int32(), replica: Int32())
		if openpty(&fds.primary, &fds.replica, nil, nil, &windowSize) != 0 {
			// Opening pty failed.
			let error = errno
			logger.error("openpty() failed: \(error, format: .darwinErrno)")
			throw SubProcessIllegalStateError.openPtyFailed(errno: error)
		}

		fileDescriptor = fds.primary

		var actions: posix_spawn_file_actions_t!
		posix_spawn_file_actions_init(&actions)
		posix_spawn_file_actions_adddup2(&actions, fds.replica, STDIN_FILENO)
		posix_spawn_file_actions_adddup2(&actions, fds.replica, STDOUT_FILENO)
		posix_spawn_file_actions_adddup2(&actions, fds.replica, STDERR_FILENO)
		defer { posix_spawn_file_actions_destroy(&actions) }

		// TODO: At some point, come up with some way to keep track of working directory changes.
		// When opening a new tab, we can switch straight to the previous tab’s working directory.
		let executable: String
		let argv: [UnsafeMutablePointer<CChar>?]
		switch Self.launchStrategy {
		case .login:
			executable = Self.loginPath ?? "/usr/bin/login"
			argv = (Self.loginArgv + [initialDirectory ?? Self.homeDirectory, Self.resolvedShellPath]).cStringArray

		case .helper:
			// Run NewTermLoginHelper directly: it does the login_tty dance (setsid, TIOCSCTTY),
			// chdirs, and execs the shell with a login-shell argv[0]. The leading dash is checked
			// by the helper’s sanity check.
			executable = Self.loginHelper ?? Self.resolvedShellPath
			argv = ["-NewTermLoginHelper", initialDirectory ?? Self.homeDirectory, Self.resolvedShellPath].cStringArray

		case .shell:
			executable = Self.resolvedShellPath
			argv = ["zsh", "--login", "-i"].cStringArray
			chdir(initialDirectory ?? Self.homeDirectory)
		}

		let environment: [String]
		if Self.launchStrategy == .helper {
			// Direct launches replace the app’s environment — the same strategy as the
			// standalone Terminal app, which is proven to work on roothide bootstraps.
			let home = Self.homeDirectory
			var user = NSUserName()
			if user.isEmpty || user.hasPrefix("/") {
				user = "mobile"
			}
			environment = [
				"PATH=\(Self.defaultPath())",
				"HOME=\(home)",
				"USER=\(user)",
				"LOGNAME=\(user)",
				"SHELL=\(Self.resolvedShellPath)",
				"TMPDIR=/tmp"
			] + Self.baseEnvp + [
				"LANG=\(localeCode)"
			]
		} else {
			environment = ProcessInfo.processInfo.environment.map { "\($0)=\($1)" } + Self.baseEnvp + [
				"LANG=\(localeCode)"
			]
		}
		let envp = environment.cStringArray

		defer {
			argv.deallocate()
			envp.deallocate()
		}

		var pid = pid_t()
		let result = ie_posix_spawn(&pid, executable, &actions, nil, argv, envp)
		close(fds.replica)
		if result != 0 {
			// Fork failed.
			close(fds.primary)
			logger.error("posix_spawn() failed: \(result, format: .darwinErrno)")
			throw SubProcessIllegalStateError.forkFailed(errno: result)
		}

		logger.debug("Process forked: \(pid)")
		childPID = pid

		// Go ahead and plug a file handle into the child tty.
		readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor!, queue: queue)
		readSource?.setEventHandler { [weak self] in
			self?.handleRead()
		}
		signalSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
		signalSource?.setEventHandler { [weak self] in
			try? self?.stop()
		}

		readSource?.activate()
		signalSource?.activate()
		delegate!.subProcessDidConnect()
	}

	func stop(fromError: Bool = false) throws {
		guard let childPID = childPID else {
			throw SubProcessIllegalStateError.notStarted
		}

		// If process is still running, send it SIGKILL and wait for termination
		if kill(childPID, 0) == 0 {
			kill(childPID, SIGKILL)

			var status = Int32()
			waitpid(childPID, &status, WUNTRACED)

			logger.debug("Process stopped with exit code: \(WEXITSTATUS(status))")
		}

		if let fileDescriptor = fileDescriptor {
			close(fileDescriptor)
		}

		self.childPID = nil
		fileDescriptor = nil
		readSource?.cancel()
		readSource = nil
		signalSource?.cancel()
		signalSource = nil

		if !fromError {
			// nil error means disconnected due to user request
			DispatchQueue.main.async {
				self.delegate?.subProcess(didDisconnectWithError: nil)
			}
		}
	}

	private func handleRead() {
		guard let fileDescriptor = fileDescriptor else {
			return
		}

		let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(BUFSIZ), alignment: MemoryLayout<CChar>.alignment)
		let bytesRead = read(fileDescriptor, buffer, Int(BUFSIZ))
		switch bytesRead {
		case -1:
			let code = errno
			switch code {
			case EAGAIN, EINTR:
				// Ignore, we’ll be called again when the source is ready.
				break

			default:
				// Something is wrong.
				DispatchQueue.main.async {
					self.delegate?.subProcess(didDisconnectWithError: SubProcessIOError.readFailed(errno: code))
				}
			}

		case 0:
			// Zero-length data is an indicator of EOF. This can happen if the user exits the terminal by
			// typing `exit` or ^D, or if there’s a catastrophic failure (e.g. /bin/login is broken).
			try? stop(fromError: false)

		default:
			// Read from output and notify delegate.
			let bytes = buffer.bindMemory(to: UTF8Char.self, capacity: bytesRead)
			let data = Array(UnsafeBufferPointer(start: bytes, count: bytesRead))
			delegate?.subProcess(didReceiveData: data)
		}
		buffer.deallocate()
	}

	func write(data: [UTF8Char]) {
		queue.async {
			guard let fileDescriptor = self.fileDescriptor else {
				return
			}
			_ = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
				Darwin.write(fileDescriptor, buffer.baseAddress!, buffer.count)
			}
		}
	}

	private var localeCode: String {
		// Try and find a locale suitable for the user. Use en_US.UTF-8 as fallback.
		// TODO: There has to be a better way to get a gettext locale out of the Apple locale. For
		// instance, a phone set to Simplified Chinese but a region of Australia will only have the
		// language zh_AU… which isn’t a thing. But gettext only has languages in country pairs, no
		// safe generic fallbacks exist, like zh-Hans in this case.
		var languages = Locale.preferredLanguages
		let preferredLocale = Preferences.shared.preferredLocale
		if preferredLocale != "",
			 Locale(identifier: preferredLocale).languageCode != nil {
			languages.insert(preferredLocale, at: 0)
		}

		for language in languages {
			let locale = Locale(identifier: language)
			if let languageCode = locale.languageCode,
				 let regionCode = locale.regionCode {
				let identifier = "\(languageCode)_\(regionCode).UTF-8"
				let url = URL(fileURLWithPath: "/usr/share/locale")/identifier
				if (try? url.checkResourceIsReachable()) == true {
					return identifier
				}
			}
		}
		return "en_US.UTF-8"
	}

	private func updateWindowSize() {
		guard let fileDescriptor = fileDescriptor else {
			return
		}

		var windowSize = screenSize.windowSize
		if ioctl(fileDescriptor, TIOCSWINSZ, &windowSize) == -1 {
			let error = errno
			logger.error("Setting screen size failed: \(error, format: .darwinErrno)")
		}
	}

	deinit {
		if childPID != nil {
			logger.error("Illegal state - SubProcess deallocated while still running")
		}

		try? stop(fromError: true)
	}

}

// MARK: - AI CLI environment (bundled Node.js runtime)

/// Lightweight helpers for the bundled AI CLI environment (Node.js, npm and
/// the `aienv` manager that NewTerm 3 AI installs into the jailbreak root).
/// Every path is probed in order, so the same build works rootful, rootless
/// (/var/jb) and RootHide (randomized root, reached through /usr/bin links).
///
/// Public so the app target (Settings → AI CLI) can use it across the
/// NewTermCommon framework boundary.
public enum AIEnv {

	static let candidatePaths = [
		"/usr/bin/aienv",
		"/usr/local/bin/aienv",
		"/var/jb/usr/bin/aienv",
		"/var/jb/usr/local/bin/aienv"
	]

	/// Whether the AI environment helpers are installed at all.
	public static var available: Bool {
		return aienvPath() != nil
	}

	static func aienvPath() -> String? {
		for path in candidatePaths {
			if FileManager.default.fileExists(atPath: path) {
				return path
			}
		}
		return nil
	}

	/// One-line summary for the settings screen.
	public static func statusSummary() -> String {
		guard let aienv = aienvPath() else {
			return "Not installed"
		}
		let binDir = (aienv as NSString).deletingLastPathComponent
		let localDir = (binDir as NSString).deletingLastPathComponent
		let nodeInstalled = FileManager.default.fileExists(atPath: localDir + "/lib/nodejs/node")
		let claudeInstalled = FileManager.default.fileExists(atPath: localDir + "/bin/claude")
		var parts = [String]()
		parts.append(nodeInstalled ? "Node.js: ready" : "Node.js: missing")
		parts.append(claudeInstalled ? "Claude Code: installed" : "Claude Code: not installed")
		return parts.joined(separator: " · ")
	}

	/// Runs `aienv <command>` through /bin/sh (with libiosexec path mapping,
	/// like terminal sessions do) and reports the exit code plus combined
	/// stdout/stderr. Completion is called on a background queue.
	public static func run(_ command: String, completion: @escaping (Int32, String) -> Void) {
		guard let aienv = aienvPath() else {
			completion(127, "aienv was not found on this device.")
			return
		}

		DispatchQueue.global(qos: .userInitiated).async {
			let binDir = (aienv as NSString).deletingLastPathComponent
			let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
				.appendingPathComponent("newterm-ai-\(UUID().uuidString).log")
			defer { try? FileManager.default.removeItem(at: outputURL) }

			let commandLine = "'\(aienv)' \(command) > '\(outputURL.path)' 2>&1"
			let pathValue = "PATH=\(binDir):/usr/bin:/bin:/usr/sbin:/sbin:/var/jb/usr/bin:/var/jb/bin"

			let argv = ["/bin/sh", "-c", commandLine].cStringArray
			let envp = [
				pathValue,
				"HOME=\(NSHomeDirectory())",
				"TERM=xterm-256color"
			].cStringArray
			defer {
				argv.deallocate()
				envp.deallocate()
			}

			var pid = pid_t()
			let result = ie_posix_spawn(&pid, "/bin/sh", nil, nil, argv, envp)
			guard result == 0 else {
				completion(result, "Couldn’t start /bin/sh (error \(result)).")
				return
			}

			var status = Int32()
			waitpid(pid, &status, 0)
			let exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1
			let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
			completion(exitCode, output)
		}
	}

}
