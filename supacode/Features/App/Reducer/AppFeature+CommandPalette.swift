import AppKit
import ComposableArchitecture

extension AppFeature {
  func reduceCommandPaletteAction(
    _ action: CommandPaletteFeature.Action,
    state: inout State
  ) -> Effect<Action> {
    switch action {
    case .setPresented(false):
      guard state.commandPalette.isPresented else { return .none }
      return restoreCommandPaletteTerminalFocusEffect(repositories: state.repositories)

    case .togglePresented:
      guard state.commandPalette.isPresented else { return .none }
      return restoreCommandPaletteTerminalFocusEffect(repositories: state.repositories)

    case .delegate(.selectWorktree(let worktreeID)):
      if state.repositories.isShowingCanvas {
        if state.repositories.worktree(for: worktreeID) == nil,
          state.repositories.repositories[id: worktreeID]?.kind == .plain
        {
          return .send(.repositories(.focusCanvasRepository(worktreeID)))
        }
        return .send(.repositories(.focusCanvasWorktree(worktreeID)))
      }
      return .send(.repositories(.selectWorktree(worktreeID)))

    case .delegate(.checkForUpdates):
      return .send(.updates(.checkForUpdates))

    case .delegate(.openSettings):
      return .merge(
        .send(.settings(.setSelection(.general))),
        .run { _ in
          await settingsWindowClient.show()
        }
      )

    case .delegate(.newWorktree):
      return .send(.repositories(.worktreeCreation(.createRandomWorktree)))

    case .delegate(.openRepository):
      return .send(.repositories(.setOpenPanelPresented(true)))

    case .delegate(.deleteWorktree(let worktreeID, let repositoryID)):
      return .send(.repositories(.worktreeLifecycle(.requestDeleteWorktree(worktreeID, repositoryID))))

    case .delegate(.viewArchivedWorktrees):
      return .send(.repositories(.selectArchivedWorktrees))

    case .delegate(.refreshWorktrees):
      return .send(.repositories(.refreshWorktrees))

    case .delegate(.jumpToLatestUnread):
      return .send(.jumpToLatestUnread)

    case .delegate(.installCLI):
      return .send(.settings(.installCLIButtonTapped(showAlert: false)))

    case .delegate(.toggleLeftSidebar):
      return .send(.toggleLeftSidebar)

    case .delegate(.toggleActiveAgentsPanel):
      return .send(.repositories(.activeAgents(.togglePanelVisibility)))

    case .delegate(.toggleCanvas):
      return .send(.repositories(.toggleCanvas))

    case .delegate(.expandCanvasCard):
      return .send(.repositories(.requestCanvasCommand(.toggleExpand)))

    case .delegate(.arrangeCanvasCards):
      return .send(.repositories(.requestCanvasCommand(.arrange)))

    case .delegate(.organizeCanvasCards):
      return .send(.repositories(.requestCanvasCommand(.organize)))

    case .delegate(.selectAllCanvasCards):
      return .send(.repositories(.requestCanvasCommand(.selectAll)))

    case .delegate(.toggleShelf):
      return .send(.repositories(.toggleShelf))

    case .delegate(.showDiff):
      guard let worktreeID = state.repositories.selectedWorktreeID,
        let worktree = state.repositories.worktree(for: worktreeID)
      else {
        return .none
      }
      let keybindings = state.resolvedKeybindings
      return .run { _ in
        await MainActor.run {
          DiffWindowManager.shared.show(
            worktreeURL: worktree.workingDirectory,
            branchName: worktree.name,
            resolvedKeybindings: keybindings
          )
        }
      }

    case .delegate(.revealInFinder):
      return .send(.openWorktree(.finder))

    case .delegate(.copyPath):
      guard let worktree = state.repositories.selectedTerminalWorktree else {
        return .none
      }
      let path = worktree.workingDirectory.path
      return .run { _ in
        await MainActor.run {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(path, forType: .string)
        }
      }

    case .delegate(.revealInSidebar):
      guard state.repositories.selectedWorktreeID != nil else { return .none }
      return .merge(
        .send(.showLeftSidebar),
        .send(.repositories(.revealSelectedWorktreeInSidebar))
      )

    case .delegate(.runScript):
      return .send(.runScript)

    case .delegate(.stopRunScript):
      return .send(.stopRunScript)

    case .delegate(.renameBranch):
      guard let worktreeID = state.repositories.selectedWorktreeID else { return .none }
      return .send(.repositories(.requestRenameBranchPrompt(worktreeID)))

    case .delegate(.openRepositorySettings(let repositoryID)):
      // Reuse the existing repo-side flow so the repo-existence guard and
      // settingsWindowClient.show() live in one place.
      return .send(.repositories(.repositoryManagement(.openRepositorySettings(repositoryID))))

    case .delegate(.togglePinWorktree(let worktreeID, let isCurrentlyPinned)):
      if isCurrentlyPinned {
        return .send(.repositories(.worktreeOrdering(.unpinWorktree(worktreeID))))
      }
      return .send(.repositories(.worktreeOrdering(.pinWorktree(worktreeID))))

    case .delegate(.runCustomCommand(let index)):
      return .send(.runCustomCommand(index))

    case .delegate(.ghosttyCommand(let action)):
      guard let worktree = actionTargetWorktree(repositories: state.repositories) else {
        return .none
      }
      return .run { _ in
        await terminalClient.send(.performBindingAction(worktree, action: action))
      }

    case .delegate(.changeFocusedTabIcon(let worktreeID)):
      guard let worktree = state.repositories.selectedTerminalWorktree,
        worktree.id == worktreeID
      else {
        return .none
      }
      return .run { _ in
        await terminalClient.send(.presentTabIconPicker(worktree))
      }

    case .delegate(.openPullRequest(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .openOnCodeHost))))

    case .delegate(.markPullRequestReady(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .markReadyForReview))))

    case .delegate(.mergePullRequest(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .merge))))

    case .delegate(.closePullRequest(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .close))))

    case .delegate(.copyFailingJobURL(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .copyFailingJobURL))))

    case .delegate(.copyCiFailureLogs(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .copyCiFailureLogs))))

    case .delegate(.rerunFailedJobs(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .rerunFailedJobs))))

    case .delegate(.openFailingCheckDetails(let worktreeID)):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .openFailingCheckDetails))))

    #if DEBUG
      case .delegate(.debugTestToast(let toast)):
        return .send(.repositories(.showToast(toast)))

      case .delegate(.debugSimulateUpdateFound):
        return .send(.updates(.debugSimulateUpdateFound))

      case .delegate(.debugLightDockNotificationDot):
        return .run { _ in await dockClient.setNotificationBadge(1) }
    #endif

    default:
      return .none
    }
  }
}
