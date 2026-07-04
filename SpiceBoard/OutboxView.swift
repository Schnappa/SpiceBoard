import SwiftUI

struct OutboxView: View {
    @Environment(UsenetStore.self) private var store
    @Binding var isPresented: Bool
    @State private var editingPost: OutboxPost? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            let queuedItems = store.outbox.filter { $0.status == "queued" }
            let sentItems = store.outbox.filter { $0.status == "sent" }
            
            List {
                Section("Warteschlange (Postausgang)") {
                    if queuedItems.isEmpty {
                        Text("Keine Entwürfe im Postausgang.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(queuedItems) { item in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.subject)
                                            .font(.system(size: 12, weight: .bold))
                                        Spacer()
                                        Text("Bereit (Klicken zum Editieren)")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange)
                                            .foregroundColor(.white)
                                            .cornerRadius(3)
                                    }
                                    HStack {
                                        Text("Gruppe: \(item.newsgroup)")
                                            .font(.system(size: 10, design: .monospaced))
                                        Spacer()
                                        Text(item.date, style: .time)
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                    .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingPost = item
                                }
                                
                                Divider()
                                
                                Button {
                                    store.outbox.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(6)
                                        .background(Color.red.opacity(0.08))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .help("Entwurf löschen")
                            }
                        }
                        .onDelete { indices in
                            let idsToDelete = indices.map { queuedItems[$0].id }
                            store.outbox.removeAll { idsToDelete.contains($0.id) }
                        }
                    }
                }
                
                Section("Gesendete Beiträge") {
                    if sentItems.isEmpty {
                        Text("Bisher keine Übertragungen in dieser Sitzung.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(sentItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.subject)
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Gruppe: \(item.newsgroup)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Label("Übertragen", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            
            // Connection Trigger
            VStack(spacing: 12) {
                if store.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Sende Beiträge & empfange News...")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.9))
                    .cornerRadius(4)
                    .padding()
                } else if store.isOffline {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.red)
                        Text("Sie sind offline. Schalten Sie das Modem in der App ein, um zu senden.")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .padding()
                } else {
                    Button {
                        store.synchronize()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down.circle")
                            Text("Verbindungsabgleich starten (Senden)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.95))
                        .cornerRadius(3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.black, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(queuedItems.isEmpty)
                    .padding()
                }
            }
            .background(Color.sysSecondaryBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sysBackground)
        .sheet(item: $editingPost) { item in
            let binding = Binding<OutboxPost>(
                get: { item },
                set: { updated in
                    if let idx = store.outbox.firstIndex(where: { $0.id == item.id }) {
                        store.outbox[idx] = updated
                    }
                }
            )
            EditOutboxPostView(
                post: binding,
                onSave: {
                    editingPost = nil
                },
                onCancel: {
                    editingPost = nil
                }
            )
            .environment(store)
        }
    }
}

struct EditOutboxPostView: View {
    @Environment(UsenetStore.self) private var store
    @Binding var post: OutboxPost
    var onSave: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Modern title header
            HStack {
                Spacer()
                Text("Beitrag editieren")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .frame(height: 32)
            .background(Color.sysSecondaryBackground)
            
            Divider()
                .background(Color.sysSeparator)
            
            Form {
                Section("Metadaten") {
                    LabeledContent("Newsgruppe") {
                        Text(post.newsgroup)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                
                Section("Inhalt") {
                    TextField("Betreff", text: $post.subject)
                        .textFieldStyle(.roundedBorder)
                    
                    TextEditor(text: $post.body)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 200)
                        .cornerRadius(4)
                        .border(Color.gray.opacity(0.3))
                }
            }
            .padding()
            
            Divider()
            
            HStack(spacing: 12) {
                Spacer()
                Button("Abbrechen") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button("Speichern") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.sysSecondaryBackground)
        }
        .frame(minWidth: 450, minHeight: 480)
    }
}
