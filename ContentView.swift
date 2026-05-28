//
//  ContentView.swift
//  FitFood
//
//  Created by Таня on 05.03.2026.
//

import SwiftUI
import VisionKit
import Foundation
import SQLite3

// MARK: - Моделі даних

struct FSProduct: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    let food_name: String
    let food_description: String
    let food_id: String

    enum CodingKeys: String, CodingKey {
        case food_name, food_description, food_id
    }
}

struct DiaryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let name: String
    let calories: Int
    let proteins: Double
    let fats: Double
    let carbs: Double
    let weight: Int

    enum CodingKeys: String, CodingKey {
        case name, calories, proteins, fats, carbs, weight
    }
}

struct Nutrients {
    let calories: Double
    let proteins: Double
    let fats: Double
    let carbs: Double
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
// MARK: - SQLite менеджер

final class LocalSQLiteManager {
    func formatNumber(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
    static let shared = LocalSQLiteManager()

    private var db: OpaquePointer?

    private init() {}

    func openDatabase() {

        if db != nil { return }

        let fileManager = FileManager.default

        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let dbURL = documentsURL.appendingPathComponent("foods.db")

        if !fileManager.fileExists(atPath: dbURL.path) {

            if let bundleURL = Bundle.main.url(forResource: "foods", withExtension: "db") {

                do {

                    try fileManager.copyItem(at: bundleURL, to: dbURL)
                    print("📦 База скопирована в Documents")

                } catch {

                    print("❌ Помилка копіювання бази:", error)
                }
            }
        }

        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {

            print("✅ SQLite база підключена:", dbURL.path)

        } else {

            print("❌ Не вдалося відкрити SQLite базу")
        }
    }

    func search(_ query: String, limit: Int = 50) -> [FSProduct] {
        guard let db else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        _ = Locale.current.language.languageCode?.identifier ?? "uk"
        
        var results: [FSProduct] = []

        let sql = """
        SELECT name_en, name_ru, name_uk, calories, protein, fat, carbs
        FROM foods
        WHERE name_uk LIKE ? COLLATE NOCASE
           OR name_ru LIKE ? COLLATE NOCASE
           OR name_en LIKE ? COLLATE NOCASE
        LIMIT ?
        """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let pattern = "%\(trimmed)%"

            sqlite3_bind_text(statement, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 4, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                let nameEN = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                _ = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let nameUK = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""

                let calories = sqlite3_column_double(statement, 3)
                let protein = sqlite3_column_double(statement, 4)
                let fat = sqlite3_column_double(statement, 5)
                let carbs = sqlite3_column_double(statement, 6)

                let language = Locale.current.language.languageCode?.identifier ?? "uk"
                let finalName: String
                if language == "en" {
                    finalName = !nameUK.isEmpty ? nameUK : nameEN
                } else {
                    finalName = !nameEN.isEmpty ? nameEN : nameUK
                }

                let product = FSProduct(
                    food_name: finalName,
                    food_description: "Cals: \(Int(calories.rounded())) | P: \(formatNumber(protein)) | F: \(formatNumber(fat)) | C: \(formatNumber(carbs))",
                    food_id: "local_\(UUID().uuidString)"
                )

                results.append(product)
            }
        } else {
            print("❌ Помилка підготовки SQL-запиту")
        }

        sqlite3_finalize(statement)
        return results
    }
    
    func addFood(
        nameEN: String,
        nameUK: String,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double
    ) {
        
        guard let db else { return }
        
        let sql = """
        INSERT INTO foods
        (name_en, name_uk, calories, protein, fat, carbs)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            
            sqlite3_bind_text(statement, 1, nameEN, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, nameUK, -1, SQLITE_TRANSIENT)
            
            sqlite3_bind_double(statement, 4, calories)
            sqlite3_bind_double(statement, 5, protein)
            sqlite3_bind_double(statement, 6, fat)
            sqlite3_bind_double(statement, 7, carbs)
            
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
        FirebaseManager.shared.addProduct(
            nameEN: nameEN,
            nameUK: nameUK,
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs
            
        )
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
}

// MARK: - Основний екран

struct ContentView: View {
    let goals = (p: 120.0, f: 60.0, c: 180.0)
    let clientId = "253d21e20d534bc7816f4e5cfe3461f0"
    let clientSecret = "e8823540a3104e35907f06338b1a16af"

    @AppStorage("useLocalDB") private var useLocalDB = true
    @AppStorage("useFatSecret") private var useFatSecret = true
    @AppStorage("useOpenFoodFacts") private var useOpenFoodFacts = true

    @AppStorage("dailyGoal") private var dailyGoal: Int = 2000
    @AppStorage("hasUserInfo") private var hasUserInfo: Bool = false
    @AppStorage("accessToken") private var accessToken = ""

    @State private var diaryEntries: [DiaryEntry] = []
    @State private var searchResults: [FSProduct] = []
    @State private var firebaseProducts: [[String: Any]] = []
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showingSettings = false
    @State private var currentSearchTask: Task<Void, Never>? = nil

    @State private var isScannerPresented = false
    @State private var showingAddFood = false
    @State private var showingWeightAlert = false
    @State private var selectedProduct: FSProduct?
    @State private var weightInput = "100"

    @State private var uWeight = ""
    @State private var uHeight = ""
    @State private var uAge = ""
    @State private var selectedGender = 0
    @State private var activityLevel = 1.2
    @State private var targetGoal = 1

    var totals: (cals: Int, p: Double, f: Double, c: Double) {
        diaryEntries.reduce((0, 0.0, 0.0, 0.0)) {
            (
                $0.0 + $1.calories,
                $0.1 + $1.proteins,
                $0.2 + $1.fats,
                $0.3 + $1.carbs
            )
        }
    }

    var body: some View {
        Group {
            if !hasUserInfo {
                registrationView
            } else {
                mainDashboard
            }
        }
        .onAppear {
            LocalSQLiteManager.shared.openDatabase()
            loadEntries()
            
            FirebaseManager.shared.listenProducts { products in
                    DispatchQueue.main.async {
                        firebaseProducts = products
                        print("Firebase products:", products)
                    }
                }

            Task {
                if useFatSecret {
                    await getToken()
                }
            }
        }
        .onDisappear {
            currentSearchTask?.cancel()
        }
    }

    // MARK: - Головний екран

    var mainDashboard: some View {
        NavigationView {
            VStack(spacing: 0) {

                List {
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView("Шукаємо продукти...")
                            Spacer()
                        }
                        .padding()
                        .listRowBackground(Color.clear)
                    }

                    if !searchResults.isEmpty {

                        Section(header: Text("Результати пошуку").bold()) {
                            ForEach(searchResults) { product in
                                foodRow(product: product)
                            }
                        }

                    } else if !searchText.isEmpty && !isSearching {

                        Section {

                            VStack(spacing: 12) {

                                Text("Продукт не знайдено")
                                    .font(.headline)

                                Text("Спробуйте іншу назву або додайте продукт вручну")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button {
                                    showingAddFood = true
                                } label: {

                                    Label("Додати продукт", systemImage: "plus.circle.fill")
                                        .font(.headline)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.vertical)
                        }

                    }
                    Section {
                        summaryHeader
                            .listRowSeparator(.hidden)
                    }
                    Section(header: Text("Сьогоднішній щоденник").bold()) {
                        if diaryEntries.isEmpty {

                            VStack(spacing: 10) {

                                Image("salad")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 70)

                                Text("Ваш щоденник порожній")
                                    .font(.headline)

                                Text("Додайте їжу через пошук.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowSeparator(.hidden)
                        
                        }
                
                        ForEach(diaryEntries) { entry in
                            diaryRow(entry: entry)
                        }
                        .onDelete(perform: deleteEntry)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .searchable(text: $searchText, prompt: "Назва або штрих-код")
            .onChange(of: searchText) { _, newValue in
                currentSearchTask?.cancel()

                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmed.isEmpty {
                    isSearching = false
                    searchResults = []
                    return
                }

                guard trimmed.count > 1 else { return }

                currentSearchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)

                    if !Task.isCancelled {
                        await runIndependentSearch(query: trimmed)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isScannerPresented = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $isScannerPresented) {
                if DataScannerViewController.isSupported {
                    ScannerView { code in
                        isScannerPresented = false
                        searchText = code
                    }
                } else {
                    Text("Камера не підтримується")
                        .padding()
                }
            }
            .sheet(isPresented: $showingSettings) {
                settingsView
            }
            .sheet(isPresented: $showingAddFood) {
                AddFoodView()
            }
            .alert("Вага порції", isPresented: $showingWeightAlert) {
                TextField("Грами", text: $weightInput)
                    .keyboardType(.numberPad)

                Button("Додати", action: confirmAdd)
                Button("Скасувати", role: .cancel) { }
            } message: {
                Text("Скільки грамів продукту ви з'їли?")
            }
        }
    }

    // MARK: - Пошук

    func runIndependentSearch(query: String) async {
        await MainActor.run {
            isSearching = true
            searchResults = []
        }

        var currentResults: [FSProduct] = []
        var seenKeys = Set<String>()
        
        let firebaseMatches: [FSProduct] = firebaseProducts.compactMap { item in
            let nameUK = item["name_uk"] as? String ?? ""
            let nameRU = item["name_ru"] as? String ?? ""
            let nameEN = item["name_en"] as? String ?? ""

            let calories = item["calories"] as? Double ?? 0
            let protein = item["protein"] as? Double ?? 0
            let fat = item["fat"] as? Double ?? 0
            let carbs = item["carbs"] as? Double ?? 0

            let allNames = [nameUK, nameEN]
            let matches = allNames.contains { $0.localizedCaseInsensitiveContains(query) }

            guard matches else { return nil }

            let finalName = !nameUK.isEmpty ? nameUK : (!nameEN.isEmpty ? nameEN : nameRU)

            return FSProduct(
                food_name: finalName,
                food_description: "Cals: \(Int(calories.rounded())) | P: \(formatNumber(protein)) | F: \(formatNumber(fat)) | C: \(formatNumber(carbs))",
                food_id: "firebase_\(UUID().uuidString)"
            )
        }

        func appendUnique(_ products: [FSProduct]) {
            for product in products {
                let key = product.food_name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if !key.isEmpty && !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    currentResults.append(product)
                }
            }
        }
        appendUnique(firebaseMatches)

        await MainActor.run {
            self.searchResults = currentResults
        }
        if useLocalDB {
            let localItems = LocalSQLiteManager.shared.search(query, limit: 50)
            appendUnique(localItems)

            await MainActor.run {
                self.searchResults = currentResults
            }
        }

        if useFatSecret {
            if accessToken.isEmpty {
                await getToken()
            }

            let translatedQuery = translateQueryForFatSecret(query)
            let fsResults = await fetchFS(query: translatedQuery)

            if !Task.isCancelled {
                appendUnique(fsResults)

                await MainActor.run {
                    self.searchResults = currentResults
                }
            }
        }

        if useOpenFoodFacts {
            let offResults = await fetchOFF(query: query)

            if !Task.isCancelled {
                appendUnique(offResults)

                await MainActor.run {
                    self.searchResults = currentResults
                }
            }
        }

        await MainActor.run {
            isSearching = false
        }
    }

        ]

        return dict[query.lowercased()] ?? query
    }

    // MARK: - FatSecret

    func fetchFS(query: String) async -> [FSProduct] {
        guard !accessToken.isEmpty else { return [] }

        var comps = URLComponents(string: "https://platform.fatsecret.com/rest/server.api")!
        comps.queryItems = [
            URLQueryItem(name: "method", value: "foods.search"),
            URLQueryItem(name: "search_expression", value: query),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let foodsRoot = json?["foods"] as? [String: Any] else {
                return []
            }

            if let foodsArray = foodsRoot["food"] as? [[String: Any]] {
                return foodsArray.map(mapFatSecretFood)
            }

            if let singleFood = foodsRoot["food"] as? [String: Any] {
                return [mapFatSecretFood(singleFood)]
            }

            return []
        } catch {
            if (error as NSError).code != -999 {
                print("FatSecret search error: \(error)")
            }
            return []
        }
    }

    func mapFatSecretFood(_ item: [String: Any]) -> FSProduct {
        let name = item["food_name"] as? String ?? "Без назви"
        let description = item["food_description"] as? String ?? ""
        let id = item["food_id"] as? String ?? UUID().uuidString

        return FSProduct(
            food_name: name,
            food_description: description,
            food_id: "fs_\(id)"
        )
    }

    func getToken() async {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { return }

        let url = URL(string: "https://oauth.fatsecret.com/connect/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let creds = "\(clientId):\(clientSecret)"
            .data(using: .utf8)?
            .base64EncodedString() ?? ""

        req.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=client_credentials&scope=basic".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("FatSecret token HTTP error: \(http.statusCode)")
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let token = json?["access_token"] as? String ?? ""

            await MainActor.run {
                self.accessToken = token
            }
        } catch {
            print("FatSecret token error: \(error)")
        }
    }

    // MARK: - OpenFoodFacts

    func fetchOFF(query: String) async -> [FSProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: trimmed)) {
            return await fetchOFFByBarcode(trimmed)
        } else {
            return await fetchOFFBySearch(trimmed)
        }
    }

    func fetchOFFByBarcode(_ barcode: String) async -> [FSProduct] {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            return []
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let product = json?["product"] as? [String: Any] else { return [] }

            let name =
                (product["product_name_uk"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (product["product_name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            guard !name.isEmpty else { return [] }

            let nutrients = product["nutriments"] as? [String: Any]
            let cals = numericValue(from: nutrients?["energy-kcal_100g"])
            let proteins = numericValue(from: nutrients?["proteins_100g"])
            let fats = numericValue(from: nutrients?["fat_100g"])
            let carbs = numericValue(from: nutrients?["carbohydrates_100g"])

            guard cals > 0 else { return [] }

            return [
                FSProduct(
                    food_name: name,
                    food_description: "Cals: \(Int(cals.rounded())) | P: \(formatNumber(proteins)) | F: \(formatNumber(fats)) | C: \(formatNumber(carbs))",
                    food_id: "off_barcode_\(barcode)"
                )
            ]
        } catch {
            if (error as NSError).code != -999 {
                print("OFF barcode error: \(error)")
            }
            return []
        }
    }

    func fetchOFFBySearch(_ query: String) async -> [FSProduct] {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "10"),
            URLQueryItem(name: "fields", value: "product_name_uk,product_name,nutriments,code")
        ]

        guard let url = comps.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let products = json?["products"] as? [[String: Any]] ?? []

            return products.compactMap { item in
                let name =
                    (item["product_name_uk"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (item["product_name"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""

                guard !name.isEmpty else { return nil }

                let nutrients = item["nutriments"] as? [String: Any]
                let cals = numericValue(from: nutrients?["energy-kcal_100g"])
                let proteins = numericValue(from: nutrients?["proteins_100g"])
                let fats = numericValue(from: nutrients?["fat_100g"])
                let carbs = numericValue(from: nutrients?["carbohydrates_100g"])

                guard cals > 0 else { return nil }

                let code = item["code"] as? String ?? UUID().uuidString

                return FSProduct(
                    food_name: name,
                    food_description: "Cals: \(Int(cals.rounded())) | P: \(formatNumber(proteins)) | F: \(formatNumber(fats)) | C: \(formatNumber(carbs))",
                    food_id: "off_\(code)"
                )
            }
        } catch {
            if (error as NSError).code != -999 {
                print("OFF search error: \(error)")
            }
            return []
        }
    }

    // MARK: - Щоденник

    func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: "diary_vPro"),
              let list = try? JSONDecoder().decode([DiaryEntry].self, from: data) else {
            diaryEntries = []
            return
        }

        diaryEntries = list
    }

    func saveEntries() {
        guard let encoded = try? JSONEncoder().encode(diaryEntries) else { return }
        UserDefaults.standard.set(encoded, forKey: "diary_vPro")
    }

    func deleteEntry(at offsets: IndexSet) {
        diaryEntries.remove(atOffsets: offsets)
        saveEntries()
    }

    func confirmAdd() {
        guard let product = selectedProduct,
              let weight = Int(weightInput),
              weight > 0 else { return }

        let nutrients = extractNutrients(from: product.food_description)
        let ratio = Double(weight) / 100.0

        let entry = DiaryEntry(
            name: product.food_name,
            calories: Int((nutrients.calories * ratio).rounded()),
            proteins: nutrients.proteins * ratio,
            fats: nutrients.fats * ratio,
            carbs: nutrients.carbs * ratio,
            weight: weight
        )

        diaryEntries.insert(entry, at: 0)
        saveEntries()

        selectedProduct = nil
        weightInput = "100"
        searchText = ""
        searchResults = []
    }

    // MARK: - Парсинг нутрієнтів

    func extractNutrients(from description: String) -> Nutrients {
        let normalized = description.replacingOccurrences(of: ",", with: ".")

        let calories =
            firstDouble(in: normalized, patterns: [
                #"Cals:\s*(\d+(?:\.\d+)?)"#,
                #"Calories:\s*(\d+(?:\.\d+)?)"#,
                #"Calories\s+(\d+(?:\.\d+)?)"#,
                #"kcal\s+(\d+(?:\.\d+)?)"#,
                #"(\d+(?:\.\d+)?)\s*kcal"#
            ]) ?? 0

        let proteins =
            firstDouble(in: normalized, patterns: [
                #"P:\s*(\d+(?:\.\d+)?)"#,
                #"Protein:\s*(\d+(?:\.\d+)?)"#,
                #"Protein\s+(\d+(?:\.\d+)?)"#
            ]) ?? 0

        let fats =
            firstDouble(in: normalized, patterns: [
                #"F:\s*(\d+(?:\.\d+)?)"#,
                #"Fat:\s*(\d+(?:\.\d+)?)"#,
                #"Fat\s+(\d+(?:\.\d+)?)"#
            ]) ?? 0

        let carbs =
            firstDouble(in: normalized, patterns: [
                #"C:\s*(\d+(?:\.\d+)?)"#,
                #"Carbs:\s*(\d+(?:\.\d+)?)"#,
                #"Carb:\s*(\d+(?:\.\d+)?)"#,
                #"Carbohydrate:\s*(\d+(?:\.\d+)?)"#,
                #"Carbohydrates:\s*(\d+(?:\.\d+)?)"#,
                #"Carbohydrates\s+(\d+(?:\.\d+)?)"#
            ]) ?? 0

        return Nutrients(
            calories: calories,
            proteins: proteins,
            fats: fats,
            carbs: carbs
        )
    }

    func firstDouble(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return Double(String(text[range]))
            }
        }
        return nil
    }

    // MARK: - UI

    var summaryHeader: some View {

        let totalMacros = totals.p + totals.f + totals.c
        let safeTotal: Double = totalMacros == 0 ? 1 : totalMacros

        let proteinPart: CGFloat = CGFloat(totals.p / safeTotal)
        let fatPart: CGFloat = CGFloat(totals.f / safeTotal)
        let carbPart: CGFloat = CGFloat(totals.c / safeTotal)

        let proteinEnd: CGFloat = proteinPart
        let fatEnd: CGFloat = proteinEnd + fatPart
        let carbEnd: CGFloat = fatEnd + carbPart

        return VStack(spacing: 16) {

            ZStack {

                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 22)

                Circle()
                    .trim(from: 0, to: proteinEnd)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: totals.p)

                Circle()
                    .trim(from: proteinEnd, to: fatEnd)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: totals.f)

                Circle()
                    .trim(from: fatEnd, to: carbEnd)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: totals.c)

                VStack(spacing: 4) {
                    Text("\(dailyGoal - totals.cals)")
                        .font(.system(size: 42, weight: .bold))

                    Text("ккал залишилось")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            VStack(spacing: 14) {

                MacroProgressRow(
                    title: "Білки",
                    value: totals.p,
                    goal: goals.p,
                    color: .blue
                )

                MacroProgressRow(
                    title: "Жири",
                    value: totals.f,
                    goal: goals.f,
                    color: .orange
                )

                MacroProgressRow(
                    title: "Вуглеводи",
                    value: totals.c,
                    goal: goals.c,
                    color: .purple
                )

            }

        }
        .padding(24)
        .frame(maxWidth: .infinity)
        
    }

    func foodRow(product: FSProduct) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.food_name)
                    .font(.headline)

                Text(product.food_description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                selectedProduct = product
                weightInput = "100"
                showingWeightAlert = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }
        }
    }

    func diaryRow(entry: DiaryEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)

                Text("\(entry.weight) г")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.calories) ккал")
                    .bold()

                Text("Б \(Int(entry.proteins)) · Ж \(Int(entry.fats)) · В \(Int(entry.carbs))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Анкета

    var registrationView: some View {
        NavigationView {
            Form {
                Section(header: Text("Фізичні параметри").bold()) {
                    HStack {
                        Image(systemName: "scalemass.fill")
                            .foregroundColor(.blue)
                            .frame(width: 30)

                        TextField("Вага (кг)", text: $uWeight)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        Image(systemName: "ruler.fill")
                            .foregroundColor(.blue)
                            .frame(width: 30)

                        TextField("Зріст (см)", text: $uHeight)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                            .frame(width: 30)

                        TextField("Вік", text: $uAge)
                            .keyboardType(.numberPad)
                    }

                    Picker("Стать", selection: $selectedGender) {
                        Text("Чоловік").tag(0)
                        Text("Жінка").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 5)
                }

                Section(header: Text("Рівень активності").bold()) {
                    Picker("Ваша активність", selection: $activityLevel) {
                        Text("Сидяча").tag(1.2)
                        Text("Низька").tag(1.375)
                        Text("Середня").tag(1.55)
                        Text("Висока").tag(1.725)
                        Text("Спортивна").tag(1.9)
                    }
                }

                Section(header: Text("Ваша ціль").bold()) {
                    Picker("Оберіть ціль", selection: $targetGoal) {
                        Text("Схуднути").tag(0)
                        Text("Підтримка").tag(1)
                        Text("Набір").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 5)
                }

                Button(action: calculateGoal) {
                    Text("Зберегти та розрахувати")
                        .frame(maxWidth: .infinity)
                        .bold()
                        .foregroundColor(.white)
                }
                .listRowBackground(Color.blue)
            }
            .navigationTitle("Анкета")
        }
    }

    func calculateGoal() {
        guard let w = Double(uWeight.replacingOccurrences(of: ",", with: ".")),
              let h = Double(uHeight.replacingOccurrences(of: ",", with: ".")),
              let a = Double(uAge) else { return }

        let bmr = (10 * w) + (6.25 * h) - (5 * a) + (selectedGender == 0 ? 5 : -161)

        var goal = bmr * activityLevel

        if targetGoal == 0 {
            goal -= 500
        } else if targetGoal == 2 {
            goal += 500
        }

        dailyGoal = max(1000, Int(goal.rounded()))
        hasUserInfo = true
    }

    // MARK: - Налаштування


    var settingsView: some View {
        NavigationView {
            Form {
                Section(header: Text("Джерела даних")) {
                    Toggle("Власна база (foods.db)", isOn: $useLocalDB)
                    Toggle("База FatSecret", isOn: $useFatSecret)
                    Toggle("База OpenFoodFacts", isOn: $useOpenFoodFacts)
                }

                Section {
                    Button("Скинути всі дані та анкету") {
                        hasUserInfo = false
                        showingSettings = false
                    }
                    .foregroundColor(.red)
                }

                Section {
                    Color.clear
                        .frame(height: 150)
                        .listRowBackground(Color.clear)
                }
                Section(footer:

                    VStack(spacing: 15) {

                        Text("Ми в соцмережах")
                            .font(.headline)

                        HStack(spacing: 40) {

                            Link(destination: URL(string: "https://www.youtube.com/@Fit_Food_Tanya")!) {
                                Image("youtube")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                            }

                            Link(destination: URL(string: "https://t.me/fit_food_group")!) {
                                Image("telegram")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                            }
                            Link(destination: URL(string: "https://www.instagram.com/shkodina_tanya_?igsh=eGRuNThpZ3l0bW1r")!) {
                                Image("instagram")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                ) { }


                }
            
    
            .navigationTitle("Налаштування")
        }
    }
}

// MARK: - Допоміжні компоненти

struct MetricView: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack {
            Text(label).bold()

            Text("\(Int(value.rounded()))г")
                .font(.caption)

            Capsule()
                .fill(color)
                .frame(width: 35, height: 4)
        }
    }
}

struct ScannerView: UIViewControllerRepresentable {
    var onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScanned: (String) -> Void

        init(onScanned: @escaping (String) -> Void) {
            self.onScanned = onScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item {
                DispatchQueue.main.async {
                    self.onScanned(barcode.payloadStringValue ?? "")
                }
            }
        }
    }
}

// MARK: - Helpers

func numericValue(from any: Any?) -> Double {
    if let value = any as? Double { return value }
    if let value = any as? Int { return Double(value) }
    if let value = any as? String {
        return Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    return 0
}

func formatNumber(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return String(Int(value))
    } else {
        return String(format: "%.1f", value)
    }
}
    func detectLanguage(_ text: String) -> String {
        if text.range(of: "[іІїЇєЄґҐ]", options: .regularExpression) != nil {
            return "uk"
        }

        return "en"
    }
struct AddFoodView: View {

    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {

        NavigationView {

            Form {

                Section(header: Text("Назва продукту")) {

                    TextField("Назва", text: $name)

                }

                Section(header: Text("Харчова цінність (на 100г)")) {

                    TextField("Калорії", text: $calories)
                        .keyboardType(.decimalPad)

                    TextField("Білки", text: $protein)
                        .keyboardType(.decimalPad)

                    TextField("Жири", text: $fat)
                        .keyboardType(.decimalPad)

                    TextField("Вуглеводи", text: $carbs)
                        .keyboardType(.decimalPad)

                }

            }
           

            .navigationTitle("Додати продукт")

            .toolbar {
                

                ToolbarItem(placement: .navigationBarLeading) {

                    Button("Скасувати") {
                        dismiss()
                    }

                }
                

                ToolbarItem(placement: .navigationBarTrailing) {

                    Button("Зберегти") {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)

                           if trimmedName.isEmpty ||
                              calories.trimmingCharacters(in: .whitespaces).isEmpty ||
                              protein.trimmingCharacters(in: .whitespaces).isEmpty ||
                              fat.trimmingCharacters(in: .whitespaces).isEmpty ||
                              carbs.trimmingCharacters(in: .whitespaces).isEmpty {

                               errorMessage = "Будь ласка, заповніть всі поля"
                               showError = true
                               return
                           }
                         

                        let c = Double(calories.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let p = Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let f = Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let carb = Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0

                        LocalSQLiteManager.shared.addFood(
                            nameEN: name,
                            nameUK: name,
                            calories: c,
                            protein: p,
                            fat: f,
                            carbs: carb
                        )

                        dismiss()

                    }
                   
                }

            }

        }
        .alert("Помилка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

  }
struct MacroProgressRow: View {

    let title: String
    let value: Double
    let goal: Double
    let color: Color

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1)
    }

    var body: some View {

        VStack(spacing: 6) {

            HStack {

                Text(title)
                    .font(.headline)

                Spacer()

                Text("\(Int(value))")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .contentTransition(.numericText())
            }

            ProgressView(value: progress)
                .tint(color)
                .animation(.easeInOut(duration: 0.6), value: progress)

        }
    }
}
