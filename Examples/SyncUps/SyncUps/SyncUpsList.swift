import ComposableArchitecture
import SwiftData
import SwiftUI

@Reducer
struct SyncUpsList {
  @ObservableState
  struct State: Equatable {
    @Presents var destination: Destination.State?
    var syncUps: IdentifiedArrayOf<SyncUp> = []

    @MainActor
    init(
      destination: Destination.State? = nil
    ) {
      self.destination = destination

      do {
        @Dependency(\.modelContainer) var modelContainer
        self.syncUps = try IdentifiedArray(
          uncheckedUniqueElements: modelContainer.mainContext.fetch(
            FetchDescriptor()
          )
        )
      } catch {
        self.destination = .alert(.dataFailedToLoad)
      }
    }
  }

  enum Action {
    case addSyncUpButtonTapped
    case confirmAddSyncUpButtonTapped
    case destination(PresentationAction<Destination.Action>)
    case dismissAddSyncUpButtonTapped
    case onDelete(IndexSet)
    case onTask
    case contextDidSave
    case syncUpTapped(id: PersistentIdentifier)
  }

  @Reducer
  struct Destination {
    @ObservableState
    enum State: Equatable {
      case add(SyncUpForm.State)
      case alert(AlertState<Action.Alert>)
    }

    enum Action {
      case add(SyncUpForm.Action)
      case alert(Alert)

      enum Alert {
        case confirmLoadMockData
      }
    }

    var body: some ReducerOf<Self> {
      Scope(state: \.add, action: \.add) {
        SyncUpForm()
      }
    }
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.uuid) var uuid
  @Dependency(\.modelContainer) var modelContainer

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .addSyncUpButtonTapped:
        state.destination = .add(SyncUpForm.State())
        return .none

      case .confirmAddSyncUpButtonTapped:
        guard case let .some(.add(editState)) = state.destination
        else { return .none }
        let syncUp = editState.syncUp
        syncUp.attendees.removeAll { attendee in
          attendee.name.allSatisfy(\.isWhitespace)
        }
        if syncUp.attendees.isEmpty {
          syncUp.attendees.append(
            editState.syncUp.attendees.first
              ?? Attendee(id: Attendee.ID(self.uuid()))
          )
        }
        state.syncUps.append(syncUp)
        state.destination = nil
        self.modelContainer.mainContext.insert(syncUp)
        try! self.modelContainer.mainContext.save()
        return .none

      case .destination(.presented(.alert(.confirmLoadMockData))):
        state.syncUps = [
          .mock,
          .designMock,
          .engineeringMock,
        ]
        return .none

      case .destination:
        return .none

      case .dismissAddSyncUpButtonTapped:
        state.destination = nil
        return .none

      case let .onDelete(indexSet):
        state.syncUps.remove(atOffsets: indexSet)
        return .none

      case .onTask:
        //state.filter = .active

        state.syncUps = try! IdentifiedArray(
          uncheckedUniqueElements: self.modelContainer.mainContext.fetch(
            FetchDescriptor()
          )
        )
        return .none
//        return .run { send in
//          for await _ in NotificationCenter.default.notifications(named: .NSManagedObjectContextDidSave) {
//            await send(.contextDidSave)
//          }
//        }

      case .contextDidSave:
//        state.syncUps = try! IdentifiedArray(
//          uncheckedUniqueElements: self.modelContainer.mainContext.fetch(
//            FetchDescriptor()
//          )
//        )
        return .none

      case .syncUpTapped:
        return .none
      }
    }
    .ifLet(\.$destination, action: \.destination) {
      Destination()
    }
//    .query { state in
//      //FetchDescriptor()
//    }
    //.query()
  }
}

struct SyncUpsListView: View {
  //@Query var syncUps: [SyncUp]
  @Bindable var store: StoreOf<SyncUpsList>

  var body: some View {
    List {
      ForEach(store.syncUps) { syncUp in
//        NavigationLink(
//          state: AppFeature.Path.State.detail(SyncUpDetail.State(syncUp: syncUp))
//        ) {
//          CardView(syncUp: syncUp)
//        }
        Button {
          store.send(.syncUpTapped(id: syncUp.persistentModelID))
        } label: {
          CardView(syncUp: syncUp)
        }
        .listRowBackground(syncUp.theme.mainColor)
      }
      .onDelete { indexSet in
        store.send(.onDelete(indexSet))
      }
    }
    .toolbar {
      Button {
        store.send(.addSyncUpButtonTapped)
      } label: {
        Image(systemName: "plus")
      }
    }
    .navigationTitle("Daily Sync-ups")
    .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
    .sheet(item: $store.scope(state: \.destination?.add, action: \.destination.add)) { store in
      NavigationStack {
        SyncUpFormView(store: store)
          .navigationTitle("New sync-up")
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Dismiss") {
                self.store.send(.dismissAddSyncUpButtonTapped)
              }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button("Add") {
                self.store.send(.confirmAddSyncUpButtonTapped)
              }
            }
          }
      }
    }
    .task {
      store.send(.onTask)
    }
  }
}

import SwiftData

extension AlertState where Action == SyncUpsList.Destination.Action.Alert {
  static let dataFailedToLoad = Self {
    TextState("Data failed to load")
  } actions: {
    ButtonState(action: .send(.confirmLoadMockData, animation: .default)) {
      TextState("Yes")
    }
    ButtonState(role: .cancel) {
      TextState("No")
    }
  } message: {
    TextState(
      """
      Unfortunately your past data failed to load. Would you like to load some mock data to play \
      around with?
      """
    )
  }
}

struct CardView: View {
  let syncUp: SyncUp

  init(syncUp: SyncUp) {
    self.syncUp = syncUp
    print(ObjectIdentifier(syncUp), syncUp.title)
  }

  var body: some View {
    let _ = Self._printChanges()
    VStack(alignment: .leading) {
      Text(self.syncUp.title)
        .font(.headline)
      Spacer()
      HStack {
        Label("\(self.syncUp.attendees.count)", systemImage: "person.3")
        Spacer()
        Label(Duration.seconds(self.syncUp.duration).formatted(.units()), systemImage: "clock")
          .labelStyle(.trailingIcon)
      }
      .font(.caption)
    }
    .padding()
    .foregroundColor(self.syncUp.theme.accentColor)
  }
}

struct TrailingIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack {
      configuration.title
      configuration.icon
    }
  }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
  static var trailingIcon: Self { Self() }
}

struct SyncUpsList_Previews: PreviewProvider {
  static var previews: some View {
    SyncUpsListView(
      store: Store(initialState: SyncUpsList.State()) {
        SyncUpsList()
      } withDependencies: { _ in 
//        $0.dataManager.load = { @Sendable _ in
//          try JSONEncoder().encode([
//            SyncUp.mock,
//            .designMock,
//            .engineeringMock,
//          ])
//        }
      }
    )

    SyncUpsListView(
      store: Store(initialState: SyncUpsList.State()) {
        SyncUpsList()
      } withDependencies: {
        $0.dataManager = .mock(initialData: Data("!@#$% bad data ^&*()".utf8))
      }
    )
    .previewDisplayName("Load data failure")
  }
}

#Preview {
  CardView(
    syncUp: SyncUp(
      attendees: [],
      duration: 60,
      meetings: [],
      theme: .bubblegum,
      title: "Point-Free Morning Sync"
    )
  )
}
