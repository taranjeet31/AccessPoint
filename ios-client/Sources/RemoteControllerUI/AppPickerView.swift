import SwiftUI
import RemoteControllerCore

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#endif

extension Image {
    init(crossPlatformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: crossPlatformImage)
        #elseif os(macOS)
        self.init(nsImage: crossPlatformImage)
        #endif
    }
}

public struct AppPickerView: View {
    public let apps: [RemoteApp]
    public let onSelectWindow: (UInt32) -> Void
    public let onSelectScreen: () -> Void

    @State private var selectedAppForSubPicker: RemoteApp? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    public init(
        apps: [RemoteApp],
        onSelectWindow: @escaping (UInt32) -> Void,
        onSelectScreen: @escaping () -> Void
    ) {
        self.apps = apps
        self.onSelectWindow = onSelectWindow
        self.onSelectScreen = onSelectScreen
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Select an App")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onSelectScreen) {
                    HStack(spacing: 6) {
                        Image(systemName: "display")
                        Text("Mirror Screen")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.15))

            if apps.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Discovering running apps on Mac...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(apps) { app in
                            AppCardView(app: app) {
                                if app.windows.count == 1, let singleWin = app.windows.first {
                                    onSelectWindow(singleWin.windowID)
                                } else {
                                    selectedAppForSubPicker = app
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .sheet(item: $selectedAppForSubPicker) { app in
            WindowSubPickerSheet(app: app) { windowID in
                selectedAppForSubPicker = nil
                onSelectWindow(windowID)
            }
        }
    }
}

struct AppCardView: View {
    let app: RemoteApp
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Window thumbnail preview or App Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))

                    if let firstWindow = app.windows.first,
                       let thumbStr = firstWindow.thumbnailJPEG,
                       let data = Data(base64Encoded: thumbStr),
                       let platformImg = PlatformImage(data: data) {
                        Image(crossPlatformImage: platformImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                            .padding(6)
                    } else if let iconStr = app.iconPNG,
                              let data = Data(base64Encoded: iconStr),
                              let platformImg = PlatformImage(data: data) {
                        Image(crossPlatformImage: platformImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                }
                .frame(height: 100)

                HStack(spacing: 6) {
                    if let iconStr = app.iconPNG,
                       let data = Data(base64Encoded: iconStr),
                       let platformImg = PlatformImage(data: data) {
                        Image(crossPlatformImage: platformImg)
                            .resizable()
                            .frame(width: 18, height: 18)
                    }

                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Text("\(app.windows.count) window\(app.windows.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct WindowSubPickerSheet: View {
    let app: RemoteApp
    let onSelect: (UInt32) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List(app.windows) { win in
                Button(action: {
                    onSelect(win.windowID)
                }) {
                    HStack(spacing: 12) {
                        if let thumbStr = win.thumbnailJPEG,
                           let data = Data(base64Encoded: thumbStr),
                           let platformImg = PlatformImage(data: data) {
                            Image(crossPlatformImage: platformImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 40)
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "window.vertical.closed")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(win.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                            Text("ID: \(win.windowID)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(app.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
