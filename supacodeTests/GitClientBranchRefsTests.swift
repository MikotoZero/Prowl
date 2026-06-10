import Foundation
import Testing

@testable import supacode

actor ShellCallStore {
  private(set) var calls: [[String]] = []

  func record(_ arguments: [String]) {
    calls.append(arguments)
  }
}

struct GitClientBranchRefsTests {
  @Test func remoteMatcherUsesRemotePrefix() {
    let remote = GitRemoteMatcher.matchingRemote(
      for: "origin/main",
      from: ["origin", "upstream"]
    )

    #expect(remote == "origin")
  }

  @Test func remoteMatcherUsesLongestRemotePrefix() {
    let remote = GitRemoteMatcher.matchingRemote(
      for: "origin-fork/main",
      from: ["origin", "origin-fork"]
    )

    #expect(remote == "origin-fork")
  }

  @Test func remoteMatcherReturnsNilForLocalBranch() {
    let remote = GitRemoteMatcher.matchingRemote(
      for: "local-branch",
      from: ["origin"]
    )

    #expect(remote == nil)
  }

  @Test func branchRefsIncludesLocalAndRemoteTrackingRefs() async throws {
    let store = ShellCallStore()
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        if arguments.contains("refs/heads") {
          return ShellOutput(stdout: "feature\nmain\nbugfix\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "origin/feature\norigin/bugfix\n", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)
    let repoRoot = URL(fileURLWithPath: "/tmp/repo")

    let refs = try await client.branchRefs(for: repoRoot)

    let expected = ["bugfix", "feature", "main", "origin/bugfix", "origin/feature"]
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    #expect(refs == expected)
    let options = try await client.branchRefOptions(for: repoRoot)
    #expect(options.contains(GitBranchRefOption(ref: "main", kind: .local)))
    #expect(options.contains(GitBranchRefOption(ref: "origin/feature", kind: .remoteTracking)))
    let calls = await store.calls
    #expect(calls.count == 4)
    let args = calls[0]
    #expect(args.first == "git")
    #expect(args.contains("for-each-ref"))
    #expect(args.contains("refs/heads"))
    #expect(args.contains("--format=%(refname:short)"))
    #expect(calls[1].contains("refs/remotes"))
  }

  @Test func branchRefsDropsOriginHead() async throws {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("refs/heads") {
          return ShellOutput(stdout: "head\nmain\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "origin/HEAD\norigin/main\n", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)
    let repoRoot = URL(fileURLWithPath: "/tmp/repo")

    let refs = try await client.branchRefs(for: repoRoot)

    #expect(refs == ["head", "main", "origin/main"])
  }

  @Test func remoteBranchRefsParsesDefaultHeadAndBranches() async throws {
    let output = """
      ref: refs/heads/main\tHEAD
      abc123\tHEAD
      abc123\trefs/heads/main
      def456\trefs/heads/feature/login
      """
    let shell = ShellClient(
      run: { _, arguments, _ in
        #expect(arguments.contains("ls-remote"))
        return ShellOutput(stdout: output, stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let refs = try await client.remoteBranchRefs(for: "git@github.com:onevcat/app.git")

    #expect(refs.defaultBaseRef == "origin/main")
    #expect(
      refs.options == [
        GitBranchRefOption(ref: "origin/feature/login", kind: .fetchedRemote),
        GitBranchRefOption(ref: "origin/main", kind: .fetchedRemote),
      ])
  }

  @Test func defaultRemoteBranchRefStripsPrefix() async throws {
    let shell = ShellClient(
      run: { _, _, _ in
        ShellOutput(stdout: "refs/remotes/origin/develop\n", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let ref = try await client.defaultRemoteBranchRef(for: URL(fileURLWithPath: "/tmp/repo"))

    #expect(ref == "origin/develop")
  }

  @Test func defaultRemoteBranchRefReturnsNilOnError() async throws {
    let shell = ShellClient(
      run: { _, _, _ in
        throw ShellClientError(command: "git", stdout: "", stderr: "boom", exitCode: 1)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let ref = try await client.defaultRemoteBranchRef(for: URL(fileURLWithPath: "/tmp/repo"))

    #expect(ref == nil)
  }

  @Test func defaultRemoteBranchRefFallsBackToOriginMain() async throws {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("symbolic-ref") {
          throw ShellClientError(command: "git", stdout: "", stderr: "missing", exitCode: 1)
        }
        if arguments.contains("rev-parse") {
          return ShellOutput(stdout: "hash", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let ref = try await client.defaultRemoteBranchRef(for: URL(fileURLWithPath: "/tmp/repo"))

    #expect(ref == "origin/main")
  }

  @Test func automaticWorktreeBaseRefUsesResolvedDefault() async throws {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("symbolic-ref") {
          return ShellOutput(stdout: "refs/remotes/origin/develop\n", stderr: "", exitCode: 0)
        }
        if arguments.contains("rev-parse") {
          return ShellOutput(stdout: "hash", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let ref = await client.automaticWorktreeBaseRef(for: URL(fileURLWithPath: "/tmp/repo"))

    #expect(ref == "origin/develop")
  }

  @Test func automaticWorktreeBaseRefReturnsNilWhenUnavailable() async throws {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("symbolic-ref") || arguments.contains("rev-parse") {
          throw ShellClientError(command: "git", stdout: "", stderr: "missing", exitCode: 1)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let ref = await client.automaticWorktreeBaseRef(for: URL(fileURLWithPath: "/tmp/repo"))

    #expect(ref == nil)
  }
}
