//
//  FirebaseManager.swift
//  FitFood
//
//  Created by Таня on 11.03.2026.
//

import FirebaseFirestore
import Foundation

class FirebaseManager {

    static let shared = FirebaseManager()

    private let db = Firestore.firestore()

    // додати продукт
    func addProduct(
        nameEN: String,
        nameRU: String,
        nameUK: String,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double
    ) {

        let data: [String: Any] = [
            "name_en": nameEN,
            "name_ru": nameRU,
            "name_uk": nameUK,
            "calories": calories,
            "protein": protein,
            "fat": fat,
            "carbs": carbs,
            "created": Timestamp()
        ]

        db.collection("products").addDocument(data: data)
    }
    func listenProducts(completion: @escaping ([[String: Any]]) -> Void) {

        db.collection("products").addSnapshotListener { snapshot, error in
            
            guard let documents = snapshot?.documents else { return }
            
            let products = documents.map { $0.data() }
            
            completion(products)
        }
    }
}
