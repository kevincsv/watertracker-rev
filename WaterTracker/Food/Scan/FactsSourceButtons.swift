import PhotosUI
import SwiftUI

/// Buttons to fill a food from a barcode or a photo of its label.
/// Calls `onFacts` with whatever could be read.
struct FactsSourceButtons: View {
    let onFacts: (NutritionFacts) -> Void

    @State private var scanningBarcode = false
    @State private var takingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Group {
            if BarcodeScannerView.isAvailable {
                Button("Escanear código de barras", systemImage: "barcode.viewfinder") {
                    scanningBarcode = true
                }
            }
            if CameraPicker.isAvailable {
                Button("Foto de la etiqueta", systemImage: "camera.viewfinder") {
                    takingPhoto = true
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Etiqueta desde Fotos", systemImage: "photo.on.rectangle")
            }
            // Attached to one row only: modifiers on a Group would repeat
            // for every row.
            .sheet(isPresented: $scanningBarcode) {
                barcodeSheet
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in
                    Task { await read(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await read(image)
                    }
                }
            }
            if isWorking {
                HStack {
                    ProgressView()
                    Text("Leyendo…")
                        .foregroundStyle(.secondary)
                }
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isWorking)
    }

    private var barcodeSheet: some View {
        NavigationStack {
            BarcodeScannerView { code in
                scanningBarcode = false
                Task { await lookUp(code) }
            }
            .ignoresSafeArea()
            .navigationTitle("Código de barras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { scanningBarcode = false }
                }
            }
        }
    }

    private func lookUp(_ code: String) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let facts = try await OpenFoodFacts.lookup(barcode: code)
            onFacts(facts)
            message = String(localized: "Datos de Open Food Facts. Revísalos con la etiqueta.")
        } catch {
            message = error.localizedDescription
        }
    }

    private func read(_ image: UIImage) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        guard let data = image.uprightJPEG() else { return }
        do {
            let facts = try await LabelReader.readLabel(from: data)
            if facts.isEmpty {
                message = String(localized: "No he podido leer la tabla. Prueba con la etiqueta recta, de cerca y con buena luz.")
            } else {
                onFacts(facts)
                message = String(localized: "Etiqueta leída. Revisa los números por si alguno no se leyó bien.")
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
