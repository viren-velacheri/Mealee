import Observation
import UIKit

@Observable
@MainActor
final class MealReviewViewModel {
    var meal: MealResponse
    let image: UIImage
    var scanPhase: ScanPhase = .detecting
    var isRelabeling = false
    var showDelta = false
    var errorMessage: String?

    init(meal: MealResponse, image: UIImage) {
        self.meal = meal
        self.image = image
    }

    func relabel(_ item: MealItem, to label: String, using api: MealeeAPI) async {
        guard label != item.label else { return }
        isRelabeling = true
        errorMessage = nil
        defer { isRelabeling = false }
        do {
            meal = try await api.relabel(mealId: meal.mealId, itemId: item.itemId, label: label)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
