import PhotosUI
import SwiftUI

/// Describe a meal, or photograph it, and get an estimate from the
/// on-device model.
struct EstimateView: View {
    let onEstimate: (NutritionFacts) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mealText = ""
    @State private var photo: UIImage?
    @State private var takingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var unavailableReason: String? { MealEstimator.unavailableReason }

    var body: some View {
        NavigationStack {
            Form {
                if let unavailableReason {
                    Section {
                        Label(unavailableReason, systemImage: "exclamationmark.triangle")
                    }
                }

                Section {
                    TextField("Por ejemplo: dos tostadas con aguacate y un huevo frito", text: $mealText, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Describe la comida")
                } footer: {
                    Text("Cuanto más detalle (cantidades, marca, cómo está cocinado), mejor la estimación.")
                }

                Section("Foto (opcional)") {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(.rect(cornerRadius: 12))
                        Button("Quitar foto", systemImage: "xmark.circle", role: .destructive) {
                            self.photo = nil
                        }
                    }
                    if CameraPicker.isAvailable {
                        Button("Hacer foto", systemImage: "camera") { takingPhoto = true }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Elegir de Fotos", systemImage: "photo.on.rectangle")
                    }
                }

                Section {
                    Button {
                        Task { await estimate() }
                    } label: {
                        HStack {
                            Text("Estimar")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isWorking || unavailableReason != nil
                              || (mealText.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil))
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                    } else {
                        Text("Lo calcula Apple Intelligence en el propio iPhone. Es una estimación: revisa los números antes de guardar.")
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Estimar comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { photo = $0 }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photo = UIImage(data: data)
                    }
                }
            }
        }
    }

    private func estimate() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            var labels: [String] = []
            if let data = photo?.uprightJPEG(maxDimension: 1200) {
                labels = (try? await LabelReader.classify(data)) ?? []
            }
            if labels.isEmpty && mealText.trimmingCharacters(in: .whitespaces).isEmpty {
                errorMessage = String(localized: "No he reconocido comida en la foto. Añade una descripción.")
                return
            }
            let facts = try await MealEstimator.estimate(description: mealText, photoLabels: labels)
            onEstimate(facts)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
