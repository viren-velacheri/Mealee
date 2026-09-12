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

    func update(_ item: MealItem, with food: FoodSearchResult, grams: Double,
                using api: MealeeAPI) async -> Bool {
        guard !isBusy else { return false }
        isRelabeling = true
        errorMessage = nil
        defer { isRelabeling = false }
        do {
            meal = try await api.updateMealItem(
                mealId: meal.mealId, itemId: item.itemId, fdcId: food.fdcId, grams: grams)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func add(_ food: FoodSearchResult, grams: Double, using api: MealeeAPI) async -> Bool {
        guard !isBusy else { return false }
        isRelabeling = true
        errorMessage = nil
        defer { isRelabeling = false }
        do {
            meal = try await api.addMealItem(mealId: meal.mealId, fdcId: food.fdcId, grams: grams)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func remove(_ item: MealItem, using api: MealeeAPI) async {
        guard !isBusy else { return }
        isRelabeling = true
        errorMessage = nil
        defer { isRelabeling = false }
        do {
            meal = try await api.deleteMealItem(mealId: meal.mealId, itemId: item.itemId)
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

@Observable
@MainActor
final class FoodSearchViewModel {
    var query: String
    var gramsText: String
    var results: [FoodSearchResult] = []
    var isSearching = false
    var errorMessage: String?

    init(query: String = "", grams: Double) {
        self.query = query
        gramsText = String(Int(grams.rounded()))
    }

    var grams: Double? {
        guard let value = Double(gramsText), 0.1...5000 ~= value else { return nil }
        return value
    }

    func search(using api: MealeeAPI) async {
        let requested = query.trimmingCharacters(in: .whitespaces)
        guard requested.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let found = try await api.searchFoods(query: requested)
            guard query.trimmingCharacters(in: .whitespaces) == requested else { return }
            results = found
            if found.isEmpty { errorMessage = "No foods found. Try a broader name." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
