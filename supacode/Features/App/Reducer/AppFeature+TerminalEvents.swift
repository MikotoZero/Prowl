import ComposableArchitecture

extension AppFeature {
  func reduceTerminalEvent(
    _ event: TerminalClient.Event,
    state: inout State
  ) -> Effect<Action> {
    switch event {
    case .customCommandSucceeded(_, let name, let durationMs):
      let message = "\(name) succeeded in \(formatCustomCommandDuration(durationMs))"
      return .send(.repositories(.showToast(.success(message))))

    case .notificationReceived(let worktreeID, let surfaceID, let title, let body):
      var effects: [Effect<Action>] = [
        .send(.repositories(.worktreeOrdering(.worktreeNotificationReceived(worktreeID))))
      ]
      if state.settings.systemNotificationsEnabled {
        effects.append(
          .run { _ in
            await systemNotificationClient.send(title, body, worktreeID, surfaceID)
          }
        )
      }
      if state.settings.notificationSoundEnabled && !state.settings.systemNotificationsEnabled {
        effects.append(
          .run { _ in
            await notificationSoundClient.play()
          }
        )
      }
      let bounceMode = state.settings.dockBounceMode
      if bounceMode != .off {
        effects.append(
          .run { _ in
            await dockClient.bounce(bounceMode)
          }
        )
      }
      return .merge(effects)

    case .notificationIndicatorChanged(let count):
      state.notificationIndicatorCount = count
      let badgeCount = state.settings.showNotificationDotOnDock ? count : 0
      return .run { _ in
        await dockClient.setNotificationBadge(badgeCount)
      }

    case .runScriptStatusChanged(let worktreeID, let isRunning):
      if isRunning {
        state.runScriptStatusByWorktreeID[worktreeID] = true
      } else {
        state.runScriptStatusByWorktreeID.removeValue(forKey: worktreeID)
      }
      return .none

    case .agentEntryChanged(let entry):
      return .send(
        .repositories(
          .activeAgents(
            .agentEntryChanged(entry, autoShowPanel: state.settings.autoShowActiveAgentsPanel)
          )
        )
      )

    case .agentEntryRemoved(let id):
      return .send(.repositories(.activeAgents(.agentEntryRemoved(id))))

    case .commandPaletteToggleRequested(let worktreeID):
      if state.commandPalette.isPresented {
        return .send(.commandPalette(.setPresented(false)))
      }
      if state.repositories.worktree(for: worktreeID) != nil {
        return .merge(
          .send(.repositories(.selectWorktree(worktreeID))),
          .send(.commandPalette(.setPresented(true)))
        )
      }
      if state.repositories.repositories[id: worktreeID]?.kind == .plain {
        return .merge(
          .send(.repositories(.selectRepository(worktreeID))),
          .send(.commandPalette(.setPresented(true)))
        )
      }
      return .send(.commandPalette(.setPresented(true)))

    case .setupScriptConsumed(let worktreeID):
      return .send(.repositories(.worktreeCreation(.consumeSetupScript(worktreeID))))

    case .fontSizeChanged(let fontSize):
      return .send(.settings(.setTerminalFontSize(fontSize)))

    case .layoutRestored(let selectedWorktreeID):
      appLogger.info("[LayoutRestore] layoutRestored: selectedWorktreeID=\(selectedWorktreeID ?? "nil")")
      // Layout restore has settled: tabs are re-created, selection is set.
      // Now apply the default view preference, which was deferred in
      // `repositoriesChanged` (via `shouldDeferDefaultView`) to avoid
      // stray spines and a selection flash.
      var effects: [Effect<Action>] = []
      if let selectedWorktreeID {
        // Plain folders use .repository selection, not .worktree
        if let repo = state.repositories.repositories[id: selectedWorktreeID],
          repo.kind == .plain
        {
          effects.append(.send(.repositories(.selectRepository(selectedWorktreeID))))
        } else {
          effects.append(.send(.repositories(.selectWorktree(selectedWorktreeID))))
        }
      }
      return .concatenate([.merge(effects), applyDefaultViewMode(into: &state)])

    case .layoutRestoreFailed(let message):
      appLogger.warning("[LayoutRestore] layoutRestoreFailed: \(message)")
      return .merge(
        .send(.repositories(.showToast(.warning(message)))),
        applyDefaultViewMode(into: &state)
      )

    case .tabCreated(let worktreeID):
      // Every tab creation (user +, CLI open, layout restore, ...)
      // marks its worktree as Shelf-visible. Layout restore in
      // particular only calls `selectWorktree` for the one active
      // worktree; other restored worktrees only surface here.
      var openedWorktreeIDs = openedWorktreeIDsForInfoWatcher(from: state.repositories)
      if state.repositories.worktree(for: worktreeID) != nil {
        openedWorktreeIDs.insert(worktreeID)
      }
      let syncedOpenedWorktreeIDs = openedWorktreeIDs
      return .merge(
        .send(.repositories(.markWorktreeOpened(worktreeID))),
        .run { _ in
          await worktreeInfoWatcher.send(.setOpenedWorktreeIDs(syncedOpenedWorktreeIDs))
        }
      )

    case .tabClosed(let worktreeID, let remainingTabs):
      // Closing the last tab retires the book from the Shelf. Other
      // closes are routine and need no Reducer-side bookkeeping.
      guard remainingTabs == 0 else { return .none }
      var openedWorktreeIDs = openedWorktreeIDsForInfoWatcher(from: state.repositories)
      openedWorktreeIDs.remove(worktreeID)
      let syncedOpenedWorktreeIDs = openedWorktreeIDs
      return .merge(
        .send(.repositories(.markWorktreeClosed(worktreeID))),
        .run { _ in
          await worktreeInfoWatcher.send(.setOpenedWorktreeIDs(syncedOpenedWorktreeIDs))
        }
      )

    case .focusChanged(_, let surfaceID):
      // Keep the Active Agents panel's keyboard-navigation anchor in sync with
      // the surface that actually has focus, so control-option-up/down steps from the right place.
      return .send(.repositories(.activeAgents(.focusedSurfaceChanged(surfaceID))))

    default:
      return .none
    }
  }
}
