import Observation
import UIKit

@Observable
@MainActor
final class MealReviewViewModel {
    var meal: MealResponse
    let image: UIImage
    var scanPhase: ScanPhase = .detecting
    var isRelabeling = false
    var isSubmitting = false
    var showDelta = false
    var errorMessage: String?

    var isBusy: Bool { isRelabeling || isSubmitting }

    init(meal: MealResponse, image: UIImage) {
        self.meal = meal
        self.image = image
    }

    func relabel(_ item: MealItem, to label: String, using api: MealeeAPI) async {
        guard label != item.label, !isBusy else { return }
        isRelabeling = true
        errorMessage = nil
        defer { isRelabeling = false }
        do {
            meal = try await api.relabel(mealId: meal.mealId, itemId: item.itemId, label: label)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirm(using api: MealeeAPI) async {
        guard !isBusy else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            meal = try await api.confirmMeal(mealId: meal.mealId)
            showDelta = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discard(using api: MealeeAPI) async -> Bool {
        guard !isBusy else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await api.discardMeal(mealId: meal.mealId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
