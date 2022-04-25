//
//  DemoTCACoordinatorApp.swift
//  DemoTCACoordinator
//
//  Created by Alexander Cyon on 2022-04-21.
//

import ComposableArchitecture
import SwiftUI
import TCACoordinators

// MARK: - APP
@main
struct DemoTCACoordinatorApp: App {
	var body: some Scene {
		WindowGroup {
//			VStack {
//				Text("`SetPIN` incorrectly backs to `Credentials`")
				AppCoordinator.View(
					store: .init(
						initialState: AppCoordinator.CoordinatorState(
							routes: [.root(.splash(.init()))]
						),
						reducer: AppCoordinator.coordinatorReducer,
						environment: AppCoordinator.Environment(
							auth: AuthState()
						)
					)
				)
				.navigationViewStyle(.stack)
//			}
		}
	}
}

struct User: Equatable {
	struct Credentials: Equatable {
		let email: String
		let password: String
	}
	struct PersonalInfo: Equatable {
		let firstname: String
		let lastname: String
	}
	let credentials: Credentials
	let personalInfo: PersonalInfo
}

typealias PIN = String

final class AuthState: ObservableObject {
	@Published var user: User? = nil
	@Published var pin: PIN? = nil
	var isAuthenticated: Bool { user != nil }
	func signOut() { user = nil }
	public init() {}
}

// MARK: - App Coord.
enum AppCoordinator {}

extension AppCoordinator {
	enum ScreenState: Equatable {
		case splash(Splash.State)
		case onboarding(OnboardingCoordinator.CoordinatorState)
		case main(Main.State)
	}
	
	enum ScreenAction {
		case splash(Splash.Action)
		case onboarding(OnboardingCoordinator.CoordinatorAction)
		case main(Main.Action)
	}
	
	struct Environment {
		let auth: AuthState
	}
	
	static let screenReducer = Reducer<ScreenState, ScreenAction, Environment>.combine(
		Splash.reducer
			.pullback(
				state: /ScreenState.splash,
				action: /ScreenAction.splash,
				environment: { Splash.Environment(auth: $0.auth) }
			),
		OnboardingCoordinator.coordinatorReducer
			.pullback(
				state: /ScreenState.onboarding,
				action: /ScreenAction.onboarding,
				environment: { OnboardingCoordinator.Environment(auth: $0.auth) }
			),
		Main.reducer
			.pullback(
				state: /ScreenState.main,
				action: /ScreenAction.main,
				environment: { Main.Environment(auth: $0.auth) }
			)
	)
	
	struct CoordinatorState: Equatable, IndexedRouterState {
		var routes: [Route<ScreenState>]
	}
	
	enum CoordinatorAction: IndexedRouterAction {
		case routeAction(Int, action: ScreenAction)
		case updateRoutes([Route<ScreenState>])
	}
	
	static let coordinatorReducer: Reducer<CoordinatorState, CoordinatorAction, Environment> = screenReducer
		.forEachIndexedRoute(environment: { Environment(auth: $0.auth) })
		.withRouteReducer(
			Reducer<CoordinatorState, CoordinatorAction, Environment> { state, action, environment in
				
				func replaceRootWithOnboarding() {
					state.routes = [
						.root(.onboarding(.initialState))
					]
				}

				switch action {
					
				case .routeAction(_, .splash(.delegate(.notSignedIn))):
					replaceRootWithOnboarding()
					
				case let .routeAction(_, .splash(.delegate(.signedIn(user)))):
					state.routes = [
						.root(.main(.init(user: user, pin: environment.auth.pin)))
					]
					
				case .routeAction(_, .main(.delegate(.signedOut))):
					environment.auth.signOut()
					replaceRootWithOnboarding()
					
				case let .routeAction(_, .onboarding(.delegate(.signedIn(user, maybePin)))):
					state.routes = [.root(.main(.init(user: user, pin: maybePin)))]
					
				default:
					break
				}
				return .none
			}
		)

	struct View: SwiftUI.View {
		typealias Store = ComposableArchitecture.Store<CoordinatorState, CoordinatorAction>
		let store: Store
		var body: some SwiftUI.View {
			TCARouter(store) { screen in
				SwitchStore(screen) {
					CaseLet(
						state: /AppCoordinator.ScreenState.splash,
						action: AppCoordinator.ScreenAction.splash,
						then: Splash.View.init
					)
					CaseLet(
						state: /AppCoordinator.ScreenState.main,
						action: AppCoordinator.ScreenAction.main,
						then: Main.View.init
					)
					CaseLet(
						state: /AppCoordinator.ScreenState.onboarding,
						action: AppCoordinator.ScreenAction.onboarding,
						then: OnboardingCoordinator.View.init
					)
				}
			}
		}
	}
}

// MARK: - Splash
enum Splash {}
extension Splash {
	
	struct State: Equatable {
		public init() {}
	}
	enum Action: Equatable {
		case delegate(Delegate)
		enum Delegate: Equatable {
			case notSignedIn, signedIn(with: User)
		}
		case onAppear
		case loadUserResult(Result<User?, Never>)
	}
	struct Environment {
		let auth: AuthState
	}
	
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .onAppear:
			return Effect<User?, Never>(value: environment.auth.user)
				.assertNoFailure()
				.delay(for: 0.8, scheduler: DispatchQueue.main)
				.catchToEffect(Action.loadUserResult)
		case let .loadUserResult(.success(maybeUser)):
			if let user = maybeUser {
				return Effect(value: .delegate(.signedIn(with: user)))
			} else {
				return Effect(value: .delegate(.notSignedIn))
			}
		case .delegate(_):
			return .none
		}
	}
	
	struct View: SwiftUI.View {
		let store: Store<State, Action>
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.pink.edgesIgnoringSafeArea(.all)
					Text("SPLASH").font(.largeTitle)
				}
				.onAppear {
					viewStore.send(.onAppear)
				}
			}
		}
	}
}

// MARK: - Main
enum Main {}
extension Main {
	
	struct State: Equatable {
		let user: User
		let pin: PIN?
	}
	enum Action: Equatable {
		case signOutButtonTapped
		case delegate(Delegate)
		enum Delegate: Equatable {
			case signedOut
		}
	}
	struct Environment {
		let auth: AuthState
	}
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .signOutButtonTapped:
			environment.auth.signOut()
			return Effect(value: .delegate(.signedOut))
		case .delegate(_):
			return .none
		}
	}
	
	
	struct View: SwiftUI.View {
		let store: Store<State, Action>
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.blue.opacity(0.65).edgesIgnoringSafeArea(.all)
					VStack {
						Text("Hello \(viewStore.user.personalInfo.firstname)!")
						Button("Sign out") {
							viewStore.send(.signOutButtonTapped)
						}
					}
				}
				.navigationTitle("Main")
			}
		}
	}
}

// MARK: - Onboarding Flow
enum OnboardingCoordinator {}
extension OnboardingCoordinator {
	
	enum ScreenState: Equatable {
		case welcome(Welcome.State)
		case termsOfService(TermsOfService.State)
		case signUp(SignUpCoordinator.CoordinatorState)
		case setupPIN(SetupPINCoordinator.CoordinatorState)
	}
	
	enum ScreenAction {
		case welcome(Welcome.Action)
		case termsOfService(TermsOfService.Action)
		case signUp(SignUpCoordinator.CoordinatorAction)
		case setupPIN(SetupPINCoordinator.CoordinatorAction)
	}
	
	struct Environment {
		let auth: AuthState
	}
	
	static let screenReducer = Reducer<ScreenState, ScreenAction, Environment>.combine(
		
		Welcome.reducer
			.pullback(
				state: /ScreenState.welcome,
				action: /ScreenAction.welcome,
				environment: { _ in Welcome.Environment() }
			),
		
		TermsOfService.reducer
			.pullback(
				state: /ScreenState.termsOfService,
				action: /ScreenAction.termsOfService,
				environment: { _ in TermsOfService.Environment() }
			),
		
		SignUpCoordinator.coordinatorReducer
			.pullback(
				state: /ScreenState.signUp,
				action: /ScreenAction.signUp,
				environment: { SignUpCoordinator.Environment(auth: $0.auth) }
			),
		
		SetupPINCoordinator.coordinatorReducer
			.pullback(
				state: /ScreenState.setupPIN,
				action: /ScreenAction.setupPIN,
				environment: { SetupPINCoordinator.Environment(auth: $0.auth) }
			)
	)
	
	struct CoordinatorState: Equatable, IndexedRouterState {
		static let initialState = Self(routes: [.root(.welcome(.init()))])
		var user: User?
		var routes: [Route<ScreenState>]
	}
	
	enum CoordinatorAction: IndexedRouterAction {
		case routeAction(Int, action: ScreenAction)
		case updateRoutes([Route<ScreenState>])
		case delegate(Delegate)
		enum Delegate {
			case signedIn(user: User, pin: PIN?)
		}
	}
	
	static let coordinatorReducer: Reducer<CoordinatorState, CoordinatorAction, Environment> = screenReducer
		.forEachIndexedRoute(environment: { Environment.init(auth: $0.auth) })
		.withRouteReducer(
			Reducer<CoordinatorState, CoordinatorAction, Environment> { state, action, environment in
				switch action {
				case .routeAction(_, .welcome(.delegate(.start))):
					state.routes.push(.termsOfService(.init()))
				case .routeAction(_,  .termsOfService(.delegate(.accept))):
					state.routes.push(
						.signUp(
							.init(routes: [
								.root(.credentials(.init()), embedInNavigationView: false)
							])
						)
					)
				case let .routeAction(_, action: ScreenAction.signUp(.delegate(.finishedSignUp(user)))):
					state.user = user
					state.routes.push(
						.setupPIN(
							.init(routes: [
								.root(.inputPIN(.init(user: user)), embedInNavigationView: false)
							])
						)
					)
				case let .routeAction(_, .setupPIN(.delegate(.finishedSettingPIN(maybePIN)))):
					guard let user = state.user else { fatalError("Incorrect impl, expected User.") }
					return Effect(value: CoordinatorAction.delegate(.signedIn(user: user, pin: maybePIN)))
				default:
					break
				}
				return .none
			}
		)
	
	struct View: SwiftUI.View {
		typealias Store = ComposableArchitecture.Store<CoordinatorState, CoordinatorAction>
		let store: Store
		
		var body: some SwiftUI.View {
			NavigationView {
				TCARouter(store) { screen in
					SwitchStore(screen) {
						CaseLet(
							state: /ScreenState.welcome,
							action: ScreenAction.welcome,
							then: Welcome.View.init
						)
						CaseLet(
							state: /ScreenState.termsOfService,
							action: ScreenAction.termsOfService,
							then: TermsOfService.View.init
						)
						CaseLet(
							state: /ScreenState.signUp,
							action: ScreenAction.signUp,
							then: SignUpCoordinator.View.init
						)
						CaseLet(
							state: /ScreenState.setupPIN,
							action: ScreenAction.setupPIN,
							then: SetupPINCoordinator.View.init
						)
					}
				}
			}
		}
	}
}

// MARK: - Welcome (Onb.)
enum Welcome {}
extension Welcome {
	
	struct State: Equatable {
	}
	enum Action: Equatable {
		case startButtonTapped
		case delegate(Delegate)
		enum Delegate: Equatable {
			case start
		}
	}
	struct Environment {
		init() {}
	}
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .startButtonTapped:
			return Effect(value: .delegate(.start))
		case .delegate(_):
			return .none
		}
	}
	
	struct View: SwiftUI.View {
		let store: Store<State, Action>
		
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.green.opacity(0.65).edgesIgnoringSafeArea(.all)
					VStack {
						Button("Start") {
							viewStore.send(.startButtonTapped)
						}
					}
				}
				.buttonStyle(.borderedProminent)
				.navigationTitle("Welcome")
			}
		}
	}
}

// MARK: - Terms (Onb.)
enum TermsOfService {}
extension TermsOfService {
	
	struct State: Equatable {
	}
	enum Action: Equatable {
		case acceptButtonTapped
		case delegate(Delegate)
		enum Delegate: Equatable {
			case accept
		}
	}
	struct Environment {
		init() {}
	}
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .acceptButtonTapped:
			return Effect(value: .delegate(.accept))
		case .delegate(_):
			return .none
		}
	}
	
	struct View: SwiftUI.View {
		let store: Store<State, Action>
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.orange.opacity(0.65).edgesIgnoringSafeArea(.all)
					VStack {
						Text("We will steal your soul.")
						Button("Accept terms") {
							viewStore.send(.acceptButtonTapped)
						}
					}
				}
				.buttonStyle(.borderedProminent)
				.navigationTitle("Terms")
			}
		}
	}
}

// MARK: - SignUpCoordinator (Onb.)
enum SignUpCoordinator {}
extension SignUpCoordinator {
	
	enum ScreenState: Equatable {
		case credentials(Credentials.State)
		case personalInfo(PersonalInfo.State)
	}
	
	enum ScreenAction {
		case credentials(Credentials.Action)
		case personalInfo(PersonalInfo.Action)
	}
	
	struct Environment {
		let auth: AuthState
	}
	
	static let screenReducer = Reducer<ScreenState, ScreenAction, Environment>.combine(
		Credentials.reducer
			.pullback(
				state: /ScreenState.credentials,
				action: /ScreenAction.credentials,
				environment: { _ in Credentials.Environment() }
			),
		PersonalInfo.reducer
			.pullback(
				state: /ScreenState.personalInfo,
				action: /ScreenAction.personalInfo,
				environment: { _ in PersonalInfo.Environment() }
			)
		
	)
	
	struct CoordinatorState: Equatable, IndexedRouterState {
		var routes: [Route<ScreenState>]
		var credentials: User.Credentials?
	}
	
	enum CoordinatorAction: IndexedRouterAction {
		case routeAction(Int, action: ScreenAction)
		case updateRoutes([Route<ScreenState>])
		case delegate(Delegate)
		enum Delegate {
			case finishedSignUp(user: User)
		}
	}
	
	static let coordinatorReducer: Reducer<CoordinatorState, CoordinatorAction, Environment> = screenReducer
		.forEachIndexedRoute(environment: { Environment(auth: $0.auth) })
		.withRouteReducer(
			Reducer<CoordinatorState, CoordinatorAction, Environment> { state, action, environment in
				switch action {
				case let .routeAction(_, .credentials(.delegate(.next(credentials)))):
					state.credentials = credentials
					state.routes.push(.personalInfo(.init()))
					
				case let .routeAction(_, .personalInfo(.delegate(.signUp(personalInfo)))):
					guard let credentials = state.credentials else { fatalError("Incorrect impl") }
					let user = User(credentials: credentials, personalInfo: personalInfo)
					environment.auth.user = user
					return Effect(value: CoordinatorAction.delegate(.finishedSignUp(user: user)))
				default:
					break
				}
				return .none
			}
		)
	
	struct View: SwiftUI.View {
		typealias Store = ComposableArchitecture.Store<CoordinatorState, CoordinatorAction>
		let store: Store
		var body: some SwiftUI.View {
			TCARouter(store) { screen in
				SwitchStore(screen) {
					CaseLet(
						state: /ScreenState.credentials,
						action: ScreenAction.credentials,
						then: Credentials.View.init
					)
					CaseLet(
						state: /ScreenState.personalInfo,
						action: ScreenAction.personalInfo,
						then: PersonalInfo.View.init
					)
				}
			}
		}
	}
}


// MARK: - Credentials (Onb.SignUp)
enum Credentials {}
extension Credentials {
	
	struct State: Equatable {
		@BindableState var email: String = "jane.doe@cool.me"
		@BindableState var password: String = "secretstuff"
		var credentials: User.Credentials? {
			guard !email.isEmpty, !password.isEmpty else { return nil }
			return .init(email: email, password: password)
		}
	}
	enum Action: Equatable, BindableAction {
		case binding(BindingAction<State>)
		case nextButtonTapped
		case delegate(Delegate)
		enum Delegate: Equatable {
			case next(User.Credentials)
		}
	}
	struct Environment {
	}
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .binding(_):
			return .none
		case .nextButtonTapped:
			guard let credentials = state.credentials else {
				fatalError()
			}
			return Effect(value: .delegate(.next(credentials)))
		case .delegate(_):
			return .none
		}
	}.binding()
	
	
	struct View: SwiftUI.View {
		let store: Store<State, Action>
		
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.yellow.opacity(0.65).edgesIgnoringSafeArea(.all)
					VStack {
						TextField("Email", text: viewStore.binding(\.$email))
						SecureField("Password", text: viewStore.binding(\.$password))
						
						Button("Next") {
							viewStore.send(.nextButtonTapped)
						}.disabled(viewStore.credentials == nil)
					}
				}
				.buttonStyle(.borderedProminent)
				.textFieldStyle(.roundedBorder)
				.navigationTitle("Credentials")
			}
		}
	}
}

// MARK: - PersonalInfo (Onb.SignUp)
enum PersonalInfo {}
extension PersonalInfo {
	
	struct State: Equatable {
		
		@BindableState var firstname: String = "Jane"
		@BindableState var lastname: String = "Doe"
		
		var personalInfo: User.PersonalInfo? {
			guard !firstname.isEmpty, !lastname.isEmpty else { return nil }
			return .init(firstname: firstname, lastname: lastname)
		}
	}
	enum Action: Equatable, BindableAction {
		case binding(BindingAction<State>)
		case signUpButtonTapped
		case delegate(Delegate)
		enum Delegate: Equatable {
			case signUp(User.PersonalInfo)
		}
	}
	struct Environment {
	}
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .binding(_):
			return .none
		case .signUpButtonTapped:
			guard let personalInfo = state.personalInfo else {
				fatalError()
			}
			return Effect(value: .delegate(.signUp(personalInfo)))
		case .delegate(_):
			return .none
		}
	}.binding()
	
	
	struct View: SwiftUI.View {
		let store: Store<State, Action>
		
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.brown.opacity(0.65).edgesIgnoringSafeArea(.all)
					VStack {
						TextField("Firstname", text: viewStore.binding(\.$firstname))
						TextField("Lastname", text: viewStore.binding(\.$lastname))
						
						Button("Sign Up") {
							viewStore.send(.signUpButtonTapped)
						}.disabled(viewStore.personalInfo == nil)
					}
				}
				.buttonStyle(.borderedProminent)
				.textFieldStyle(.roundedBorder)
				.navigationTitle("Personal Info")
			}
		}
	}
}


// MARK: - SetPIN SubFlow (Onb.)
enum SetupPINCoordinator {}
extension SetupPINCoordinator {
	
	enum ScreenState: Equatable {
		case inputPIN(InputPIN.State)
		case confirmPIN(ConfirmPIN.State)
	}
	
	enum ScreenAction {
		case inputPIN(InputPIN.Action)
		case confirmPIN(ConfirmPIN.Action)
	}
	
	struct Environment {
		let auth: AuthState
	}
	
	static let screenReducer = Reducer<ScreenState, ScreenAction, Environment>.combine(
		InputPIN.reducer
			.pullback(
				state: /ScreenState.inputPIN,
				action: /ScreenAction.inputPIN,
				environment: { _ in InputPIN.Environment() }
			),
		ConfirmPIN.reducer
			.pullback(
				state: /ScreenState.confirmPIN,
				action: /ScreenAction.confirmPIN,
				environment: { _ in ConfirmPIN.Environment() }
			)
		
	)
	
	struct CoordinatorState: Equatable, IndexedRouterState {
		var routes: [Route<ScreenState>]
	}
	
	enum CoordinatorAction: IndexedRouterAction {
		case routeAction(Int, action: ScreenAction)
		case updateRoutes([Route<ScreenState>])
		case delegate(Delegate)
		enum Delegate: Equatable {
			case finishedSettingPIN(PIN?)
		}
	}
	
	static let coordinatorReducer: Reducer<CoordinatorState, CoordinatorAction, Environment> = screenReducer
		.forEachIndexedRoute(environment: { Environment(auth: $0.auth) })
		.withRouteReducer(
			Reducer<CoordinatorState, CoordinatorAction, Environment> { state, action, environment in
				switch action {
					//	private func toConfirmPIN(pin: PIN) {
					//		routes.push(.confirmPIN(pin))
					//	}
					//
					//
					//	private func done(pin: PIN) {
					//		auth.pin = pin
					//		doneSettingPIN(pin)
					//	}
					//
					//	private func skip() {
					//		doneSettingPIN(nil)
					//	}
				case let .routeAction(_, .inputPIN(.delegate(.finishedInputtingPIN(pin)))):
					state.routes.push(.confirmPIN(.init(pinToConfirm: pin)))
				case .routeAction(_, .inputPIN(.delegate(.skip))):
					return Effect(value: .delegate(.finishedSettingPIN(nil)))
				case let .routeAction(_, .confirmPIN(.delegate(.confirmedPIN(pin)))):
					environment.auth.pin = pin
					return Effect(value: .delegate(.finishedSettingPIN(pin)))
				case .routeAction(_, .confirmPIN(.delegate(.skip))):
					return Effect(value: .delegate(.finishedSettingPIN(nil)))
					
				default:
					break
				}
				return .none
			}
		)
	
	
	struct View: SwiftUI.View {
		typealias Store = ComposableArchitecture.Store<CoordinatorState, CoordinatorAction>
		let store: Store
		
		var body: some SwiftUI.View {
			TCARouter(store) { screen in
				SwitchStore(screen) {
					CaseLet(
						state: /ScreenState.inputPIN,
						action: ScreenAction.inputPIN,
						then: InputPIN.View.init
					)
					CaseLet(
						state: /ScreenState.confirmPIN,
						action: ScreenAction.confirmPIN,
						then: ConfirmPIN.View.init
					)
				}
			}
		}
	}
}

// MARK: - InputPINView (Onb.SetPIN)
enum InputPIN {}
extension InputPIN {
	
	struct State: Equatable {
		let firstname: String
		@BindableState var pin: String
		init(user: User, pin: String = "1234") {
			self.firstname = user.personalInfo.firstname
			self.pin = pin
		}
	}
	
	enum Action: Equatable, BindableAction {
		case binding(BindingAction<State>)
		case nextButtonTapped, skipButtonTapped
		case delegate(Delegate)
		enum Delegate: Equatable {
			case finishedInputtingPIN(PIN)
			case skip
		}
	}
	struct Environment {
	}
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .binding(_):
			return .none
		case .skipButtonTapped:
			return Effect(value: .delegate(.skip))
			
		case .nextButtonTapped:
			assert(!state.pin.isEmpty)
			return Effect(value: .delegate(.finishedInputtingPIN(state.pin)))
		case .delegate(_):
			return .none
		}
	}.binding()
	
	
	struct View: SwiftUI.View {
		let store: Store<State, Action>
		
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.red.opacity(0.65).edgesIgnoringSafeArea(.all)
					VStack {
						Text("Hey \(viewStore.firstname), secure your app by setting a PIN.").lineLimit(2)
						SecureField("PIN", text: viewStore.binding(\.$pin))
						Button("Next") {
							viewStore.send(.nextButtonTapped)
						}.disabled(viewStore.pin.isEmpty)
					}
				}
				.navigationTitle("Set PIN")
				.toolbar {
					ToolbarItem(placement: .navigationBarTrailing) {
						Button("Skip") {
							viewStore.send(.skipButtonTapped)
						}
					}
				}
				.buttonStyle(.borderedProminent)
				.textFieldStyle(.roundedBorder)
			}
		}
	}
}

// MARK: - ConfirmPINView (Onb.SetPIN)
enum ConfirmPIN {}
extension ConfirmPIN {
	
	struct State: Equatable {
		let pinToConfirm: PIN
		@BindableState var pin: String
		init(pinToConfirm: PIN, pin: String = "1234") {
			self.pinToConfirm = pinToConfirm
			self.pin = pin
		}
	}
	
	enum Action: Equatable, BindableAction {
		case binding(BindingAction<State>)
		case confirmPINButtonTapped, skipButtonTapped
		case delegate(Delegate)
		enum Delegate: Equatable {
			case confirmedPIN(PIN)
			case skip
		}
	}
	struct Environment {
	}
	static let reducer = Reducer<State, Action, Environment> { state, action, environment in
		switch action {
		case .binding(_):
			return .none
		case .skipButtonTapped:
			return Effect(value: .delegate(.skip))
			
		case .confirmPINButtonTapped:
			assert(state.pin == state.pinToConfirm)
			return Effect(value: .delegate(.confirmedPIN(state.pin)))
		case .delegate(_):
			return .none
		}
	}.binding()
	
	
	struct View: SwiftUI.View {
		
		let store: Store<State, Action>
		
		var body: some SwiftUI.View {
			WithViewStore(store) { viewStore in
				ZStack {
					Color.red.opacity(0.65).edgesIgnoringSafeArea(.all)
					VStack {
						SecureField("Confirm PIN", text: viewStore.binding(\.$pin))
						Button("Confirm PIN") {
							viewStore.send(.confirmPINButtonTapped)
						}.disabled(viewStore.pin != viewStore.pinToConfirm)
					}
				}
				.navigationTitle("Confirm PIN")
				.toolbar {
					ToolbarItem(placement: .navigationBarTrailing) {
						Button("Skip") {
							viewStore.send(.skipButtonTapped)
						}
					}
				}
				.buttonStyle(.borderedProminent)
				.textFieldStyle(.roundedBorder)
			}
		}
	}
}
