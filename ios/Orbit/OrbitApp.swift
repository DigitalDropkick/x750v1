import SwiftUI

@main
struct OrbitApp: App {
    @StateObject private var model = OrbitModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.orbitNight.ignoresSafeArea()
                // The native connection screen owns interaction until sign-in finishes.
                ConsoleWebView(model:model).ignoresSafeArea(.container).privacySensitive()
                    .opacity(model.connected ? 1 : 0)
                    .allowsHitTesting(model.connected && !model.locked && !model.obscured)
                    .accessibilityHidden(!model.connected || model.locked || model.obscured)
                if model.connected {
                    if model.pageLoading && !model.locked {
                        VStack(spacing:14) { ProgressView(); Text("Opening your workspace…").font(.callout) }
                            .padding(24).background(Color.orbitPanel,in:RoundedRectangle(cornerRadius:20))
                    }
                    if model.locked || model.obscured {
                        Color.orbitNight.ignoresSafeArea()
                        VStack(spacing:24) {
                            Image(systemName:"faceid").font(.system(size:52)).foregroundStyle(Color.orbitCyan)
                            Text("Your workspace is locked").font(.title2.bold())
                            Text("Jobs continue on your router.").foregroundStyle(.secondary)
                            Button("Unlock workspace") { model.resume() }.buttonStyle(OrbitButton())
                        }.padding(28)
                    }
                } else { ConnectionView(model:model) }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented:$model.connectionSheet) { ConnectionView(model:model).presentationDragIndicator(.visible) }
            .sheet(item:$model.sharedFile) { file in FileShare(url:file.url) }
            .overlay(alignment:.top) {
                if !model.locked && !model.obscured, let message = model.downloadMessage {
                    HStack { ProgressView(); Text(message).font(.caption) }
                        .padding(14).background(.ultraThinMaterial,in:Capsule()).padding(.top,8)
                }
            }
            .onChange(of:scenePhase) { _,phase in
                model.obscured = phase != .active
                if phase == .background { model.locked = model.connected }
                if phase == .active { model.resume() }
            }
            .task {
                if UserDefaults.standard.string(forKey:"orbit.endpoint") != nil { model.connect() }
            }
        }
    }
}

extension Color {
    static let orbitNight = Color(red:8/255,green:13/255,blue:25/255)
    static let orbitCyan = Color(red:131/255,green:231/255,blue:244/255)
    static let orbitPanel = Color(red:17/255,green:28/255,blue:48/255)
}
struct OrbitButton: ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:16,weight:.semibold)).frame(maxWidth:.infinity,minHeight:52)
            .foregroundStyle(Color.orbitNight)
            .background(LinearGradient(colors:[.orbitCyan,Color(red:0.48,green:0.76,blue:1)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:17))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct Planet: View {
    var body:some View {
        ZStack {
            Canvas { context,size in
                for i in 0..<42 {
                    let x = CGFloat((i * 71 + 13) % 307) / 307 * size.width
                    let y = CGFloat((i * 43 + 7) % 211) / 211 * size.height
                    let r:CGFloat = i % 5 == 0 ? 1.3 : 0.7
                    context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:r*2,height:r*2)),with:.color(.white.opacity(i % 3 == 0 ? 0.7 : 0.25)))
                }
            }
            Circle().fill(RadialGradient(colors:[Color(red:0.61,green:0.91,blue:1),Color(red:0.19,green:0.48,blue:0.65),Color(red:0.07,green:0.16,blue:0.30),.orbitNight],center:.topLeading,startRadius:0,endRadius:190))
                .frame(width:156,height:156).shadow(color:.orbitCyan.opacity(0.12),radius:32)
            Ellipse().stroke(Color.orbitCyan.opacity(0.5),lineWidth:1).frame(width:260,height:82).rotationEffect(.degrees(-28))
            Ellipse().stroke(Color.orbitCyan.opacity(0.13),lineWidth:1).frame(width:296,height:110).rotationEffect(.degrees(-28))
            Circle().fill(.white).frame(width:6,height:6).shadow(color:.orbitCyan,radius:8).offset(x:94,y:-60)
        }.frame(height:214).accessibilityHidden(true)
    }
}
struct ConnectionView: View {
    @ObservedObject var model:OrbitModel
    @FocusState private var editing:Bool
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(alignment:.center) {
                    HStack(spacing:10) {
                        Image(systemName:"circle.hexagongrid").font(.system(size:29,weight:.light)).foregroundStyle(Color.orbitCyan)
                        VStack(alignment:.leading,spacing:3) {
                            Text("ORBIT").font(.system(size:24,weight:.bold,design:.rounded)).tracking(5)
                            Text("DIGITAL DROPKICK").font(.system(size:8,weight:.medium,design:.monospaced)).tracking(2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("PRIVATE BETA").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1)
                        .padding(.horizontal,10).padding(.vertical,8).background(.white.opacity(0.05),in:Capsule()).foregroundStyle(Color.orbitCyan)
                }
                if !model.connected && !editing { Planet().padding(.vertical,-8) }
                VStack(alignment:.leading,spacing:8) {
                    Text(model.connected ? "Your connection." : "Your field kit.\nIn orbit.")
                        .font(.system(size:model.connected ? 32 : 40,weight:.bold,design:.rounded)).tracking(-1.5)
                    Text(model.connected ? "Reconnect, switch routes, or manage saved sign-in." : "Connect your X750. Bring your complete toolkit into the field.")
                        .font(.system(size:15)).foregroundStyle(Color(red:0.67,green:0.74,blue:0.84)).fixedSize(horizontal:false,vertical:true)
                }
                VStack(alignment:.leading,spacing:16) {
                    Text("CONNECT TO YOUR APPLIANCE").font(.system(size:10,weight:.medium,design:.monospaced)).tracking(1.5).foregroundStyle(Color.orbitCyan)
                    HStack(spacing:10) {
                        route("Router Wi-Fi",symbol:"wifi",address:"https://192.168.8.1")
                        route("Tailscale",symbol:"point.3.connected.trianglepath.dotted",address:"https://100.122.115.85")
                    }
                    VStack(alignment:.leading,spacing:7) {
                        Text("Router address").font(.caption).foregroundStyle(.secondary)
                        TextField("https://192.168.8.1",text:$model.address).keyboardType(.URL).textContentType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                            .accessibilityIdentifier("router-address")
                            .onChange(of:model.address) { _,_ in model.candidateFingerprint = nil }
                    }
                    Divider().overlay(.white.opacity(0.06))
                    HStack(spacing:16) {
                        VStack(alignment:.leading,spacing:7) {
                            Text("LuCI username").font(.caption).foregroundStyle(.secondary)
                            TextField("root",text:$model.username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                                .accessibilityIdentifier("router-username")
                        }.frame(maxWidth:100)
                        VStack(alignment:.leading,spacing:7) {
                            Text("Password").font(.caption).foregroundStyle(.secondary)
                            SecureField("Saved or enter password",text:$model.password).textContentType(.password).focused($editing)
                                .accessibilityIdentifier("router-password")
                                .onSubmit { editing = false; model.connect() }
                        }
                    }
                    Toggle(isOn:$model.saveLogin) {
                        Label("Save sign-in with Face ID / passcode",systemImage:"faceid").font(.caption)
                    }.tint(.orbitCyan)
                        .accessibilityIdentifier("save-login")
                }
                .padding(20).background(Color.orbitPanel,in:RoundedRectangle(cornerRadius:24))
                .overlay(RoundedRectangle(cornerRadius:24).stroke(.white.opacity(0.09)))
                .disabled(model.connecting)
                if let fingerprint = model.candidateFingerprint {
                    VStack(alignment:.leading,spacing:12) {
                        Label("Verify your router",systemImage:"checkmark.shield").font(.headline)
                        Text("Match this SHA-256 certificate fingerprint with the router’s trusted installation record before continuing.").font(.caption).foregroundStyle(.secondary)
                        Text(fingerprint).font(.system(size:12,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                        Button("Fingerprint verified · trust router") { editing = false; model.trustCertificate() }.buttonStyle(OrbitButton())
                            .accessibilityIdentifier("trust-router")
                        Button("Cancel") { model.candidateFingerprint = nil }.frame(maxWidth:.infinity,minHeight:44)
                    }.padding(20).background(Color.orbitPanel,in:RoundedRectangle(cornerRadius:24))
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(Color(red:1,green:0.81,blue:0.65)).fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("connection-message")
                }
                if model.connecting {
                    HStack { ProgressView(); Text(model.connectionProgress).font(.callout).accessibilityIdentifier("connection-progress") }.frame(maxWidth:.infinity)
                    Button("Cancel connection") { model.cancelConnection() }.frame(maxWidth:.infinity,minHeight:44)
                } else if model.candidateFingerprint == nil {
                    Button { editing = false; model.connect() } label: {
                        HStack { Text(model.connected ? "Reconnect to router" : "Connect to router"); Image(systemName:"arrow.up.right") }
                    }.buttonStyle(OrbitButton()).accessibilityIdentifier("connect-router")
                }
                if model.connected {
                    Button("Return to workspace") { model.connectionSheet = false }.frame(maxWidth:.infinity,minHeight:44)
                    HStack {
                        Button("Forget saved sign-in") { model.forgetLogin() }
                        Spacer()
                        Button("Disconnect") { model.disconnect() }
                    }.font(.caption).padding(.vertical,8)
                }
                Label("Tools run on your router. Results stay with your jobs.",systemImage:"antenna.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.bottom,12)
            }.padding(26).frame(maxWidth:520).frame(maxWidth:.infinity)
        }.background(Color.orbitNight).scrollDismissesKeyboard(.interactively)
    }
    private func route(_ title:String,symbol:String,address:String)->some View {
        Button { model.address = address; model.candidateFingerprint = nil } label: {
            Label(title,systemImage:symbol).font(.system(size:12,weight:.medium))
                .frame(maxWidth:.infinity,minHeight:44)
                .background(model.address == address ? Color.orbitCyan.opacity(0.13) : .white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(model.address == address ? Color.orbitCyan.opacity(0.45) : .clear))
        }.foregroundStyle(model.address == address ? Color.orbitCyan : .secondary)
    }
}
