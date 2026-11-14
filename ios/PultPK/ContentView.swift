import SwiftUI
import UIKit

private let bgColor = Color(red: 0.063, green: 0.071, blue: 0.086)
private let amber = Color(red: 0.941, green: 0.706, blue: 0.161)

struct ContentView: View {
    @AppStorage("pcIP") private var pcIP = "192.168.1.15"
    @AppStorage("pcPort") private var pcPort = "8000"
    @AppStorage("mac") private var mac = "74-56-3C-4D-D2-0E"
    @State private var online = false
    @State private var misses = 0
    @State private var waking = false
    @State private var message = ""
    @State private var showSettings = false

    private var statusText: String {
        online ? "ПК включён" : (waking ? "Загружается…" : "ПК выключен")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(online ? Color.green : Color.red).frame(width: 10, height: 10)
                Text(statusText).font(.subheadline).foregroundColor(.gray)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if online, let url = URL(string: "http://\(pcIP):\(pcPort)") {
                PulseWebView(url: url).id(url)
            } else {
                offlineView
            }
        }
        .background(bgColor.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(pcIP: $pcIP, pcPort: $pcPort, mac: $mac)
        }
        .task { await pollLoop() }
    }

    private var offlineView: some View {
        VStack(spacing: 16) {
            Spacer()
            Button(action: wake) {
                Text("Включить ПК")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(amber)
                    .cornerRadius(14)
            }
            Text(message)
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private func wake() {
        let m = mac, ip = pcIP
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        message = "Отправляю сигнал…"
        Task {
            let ok = await Task.detached { WakeOnLAN.send(mac: m, pcIP: ip) }.value
            if ok {
                waking = true
                message = "Сигнал отправлен. Компьютер загрузится за 10–40 секунд."
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                waking = false
            } else {
                message = "Не удалось отправить. Проверьте MAC-адрес в настройках и разрешите приложению «Локальная сеть» в Настройках iPhone."
            }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            let up = await WakeOnLAN.isOnline(host: pcIP, port: pcPort)
            if up {
                misses = 0
                if !online { online = true; waking = false; message = "" }
            } else {
                misses += 1
                if misses >= 3 && online { online = false }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
}

struct SettingsView: View {
    @Binding var pcIP: String
    @Binding var pcPort: String
    @Binding var mac: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Компьютер"),
                        footer: Text("Включение работает в домашней Wi-Fi сети. MAC берите у Ethernet-адаптера ПК.")) {
                    TextField("IP-адрес", text: $pcIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Порт пульта", text: $pcPort).keyboardType(.numberPad)
                    TextField("MAC-адрес", text: $mac)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
}
