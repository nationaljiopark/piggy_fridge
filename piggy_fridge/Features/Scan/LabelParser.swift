import Foundation

// Turns text read from a food label (or from a barcode lookup) into a food for My Food.
//
// Order of matching, same as the Figma / impact-method notes:
// 1. one of the 100 foods in FoodPresets.json  -> its icon, storage, weight, price and CO2e
// 2. a category guessed from keywords          -> median numbers from freshmate_category_fallbacks.csv
// 3. nothing found                             -> "Other (unknown)" and the person names it

// MARK: - Result of one reading

struct ScanCandidate: Equatable {
    var preset: FoodPreset?
    var category: String?
    var date: Date?
    var dateType: DateType?
    var weightKg: Double?
    var priceGBP: Double?
    /// Storage printed on the label ("Keep refrigerated", "Keep frozen", "Store in a cool, dry place").
    var storage: Storage?
    /// Real product name from the barcode, e.g. "Heinz Baked Beans". Once a barcode is read,
    /// noisy text from the label no longer changes what the food is.
    var productName: String?
    var fromBarcode = false

    var isEmpty: Bool { preset == nil && category == nil && date == nil && productName == nil }

    /// Newer readings fill in or replace what we already know.
    mutating func merge(_ other: ScanCandidate) {
        if other.fromBarcode {
            preset = other.preset
            category = other.category ?? other.preset?.category
            productName = other.productName
            fromBarcode = true
        } else if !fromBarcode {
            if let p = other.preset {
                preset = p
                category = p.category
            } else if preset == nil, let c = other.category {
                category = c
            }
        }
        date = other.date ?? date
        dateType = other.dateType ?? dateType
        weightKg = other.weightKg ?? weightKg
        priceGBP = other.priceGBP ?? priceGBP
        storage = other.storage ?? storage
    }
}

// MARK: - Category fallbacks (freshmate_category_fallbacks.csv)

struct CategoryFallback {
    let category: String
    let weightKg: Double
    let priceGBP: Double
    let co2ePerKg: Double
    let storage: Storage
    let dateType: DateType
    let keywords: [String]

    static let unknown = CategoryFallback(category: "Other (unknown)", weightKg: 0.4, priceGBP: 1.6, co2ePerKg: 1.79,
                                          storage: .fridge, dateType: .bestBefore, keywords: [])

    /// Order matters: when two categories match equally, the earlier one wins.
    static let all: [CategoryFallback] = [
        CategoryFallback(category: "Frozen", weightKg: 0.5, priceGBP: 2.5, co2ePerKg: 1.53, storage: .freezer, dateType: .bestBefore,
                         keywords: ["frozen", "freezer", "ice", "sorbet"]),
        CategoryFallback(category: "Chilled & ready", weightKg: 0.4, priceGBP: 2.0, co2ePerKg: 2.19, storage: .fridge, dateType: .useBy,
                         keywords: ["meal", "soup", "sandwich", "sushi", "quiche", "pie", "dip", "curry", "lasagne", "ready", "pizza", "noodle pot", "wrap pot"]),
        CategoryFallback(category: "Sauces", weightKg: 0.4, priceGBP: 1.9, co2ePerKg: 4.67, storage: .cupboard, dateType: .bestBefore,
                         keywords: ["sauce", "ketchup", "mayo", "mayonnaise", "mustard", "dressing", "pesto", "gravy", "relish", "chutney", "vinegar"]),
        CategoryFallback(category: "Dairy & eggs", weightKg: 0.3, priceGBP: 1.73, co2ePerKg: 14.27, storage: .fridge, dateType: .useBy,
                         keywords: ["milk", "cheese", "yoghurt", "yogurt", "cream", "egg", "butter", "dairy", "kefir", "custard", "skyr"]),
        CategoryFallback(category: "Meat", weightKg: 0.5, priceGBP: 3.5, co2ePerKg: 12.31, storage: .fridge, dateType: .useBy,
                         keywords: ["chicken", "beef", "pork", "lamb", "turkey", "steak", "mince", "sausage", "bacon", "ham", "burger", "meatball", "duck", "gammon"]),
        CategoryFallback(category: "Fish", weightKg: 0.2, priceGBP: 2.75, co2ePerKg: 13.63, storage: .fridge, dateType: .useBy,
                         keywords: ["fish", "salmon", "tuna", "cod", "haddock", "prawn", "shrimp", "mackerel", "trout", "seafood", "seabass", "sardine"]),
        CategoryFallback(category: "Fruit", weightKg: 0.6, priceGBP: 1.6, co2ePerKg: 1.05, storage: .fridge, dateType: .bestBefore,
                         keywords: ["fruit", "apple", "pear", "berry", "grape", "banana", "orange", "lemon", "lime", "peach", "plum", "cherry", "kiwi", "melon", "mango", "nectarine", "satsuma"]),
        CategoryFallback(category: "Veg & salad", weightKg: 0.38, priceGBP: 0.95, co2ePerKg: 0.53, storage: .fridge, dateType: .useBy,
                         keywords: ["salad", "veg", "vegetable", "lettuce", "spinach", "kale", "cabbage", "pepper", "onion", "carrot", "potato", "cucumber", "tomato", "mushroom", "pea", "leek", "herb", "rocket", "sprout", "corn", "squash", "beetroot", "radish", "chilli"]),
        CategoryFallback(category: "Bakery", weightKg: 0.41, priceGBP: 1.35, co2ePerKg: 1.57, storage: .cupboard, dateType: .useBy,
                         keywords: ["bread", "bun", "roll", "bagel", "cake", "croissant", "muffin", "pastry", "baguette", "loaf", "naan", "wrap", "brioche", "scone"]),
        CategoryFallback(category: "Cupboard", weightKg: 0.5, priceGBP: 1.4, co2ePerKg: 2.09, storage: .cupboard, dateType: .bestBefore,
                         keywords: ["pasta", "rice", "cereal", "oat", "flour", "sugar", "biscuit", "crisp", "noodle", "tin", "tinned", "bean", "lentil", "chickpea", "nut", "chocolate", "tea", "coffee", "honey", "jam", "spread"])
    ]

    static func named(_ name: String) -> CategoryFallback {
        all.first { $0.category == name } ?? unknown
    }
}

// MARK: - Parser

enum LabelParser {

    /// Read everything we can from the text lines the camera sees right now.
    static func read(_ texts: [String], presets: [FoodPreset], now: Date = .now) -> ScanCandidate {
        let lines = texts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result = ScanCandidate()
        if let found = findDate(in: lines, now: now) {
            result.date = found.date
            result.dateType = found.type
        }
        result.weightKg = findWeightKg(in: lines)
        result.priceGBP = findPrice(in: lines)
        result.storage = findStorage(in: lines)

        let words = Set(lines.flatMap { tokens($0) })
        if let preset = matchPreset(words: words, presets: presets) {
            result.preset = preset
            result.category = preset.category
        } else if let category = guessCategory(words: words) {
            result.category = category
        }
        return result
    }

    /// Category from loose text (used for barcode category tags).
    static func category(in texts: [String]) -> String? {
        guessCategory(words: Set(texts.flatMap { tokens($0) }))
    }

    // MARK: Dates

    private static let monthIndex: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    private static let namedMonthPattern =
        "\\b(\\d{1,2})\\s*(?:st|nd|rd|th)?[\\s\\-/.]*(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\b\\.?[\\s\\-/.]*(\\d{4}|\\d{2})?(?!\\d)"

    private static let numericPattern = "\\b(\\d{1,2})[/.\\-](\\d{1,2})[/.\\-](\\d{4}|\\d{2})\\b"

    /// Dates for the shop, not for you. A date next to these words is never used.
    private static let shopDateWords = ["display until", "display by", "sell by", "display till", "show until"]

    private static func isShopDate(_ lower: String) -> Bool {
        let squeezed = lower.replacingOccurrences(of: "-", with: " ")
        return shopDateWords.contains { squeezed.contains($0) }
    }

    private static func findDate(in lines: [String], now: Date) -> (date: Date, type: DateType?)? {
        // 1. A date next to "Use by" / "Best before" (lines about the shop's date are left out).
        for i in lines.indices {
            guard let type = dateType(in: lines[i].lowercased()) else { continue }
            let window = lines[max(0, i - 1)...min(lines.count - 1, i + 1)]
                .filter { $0 == lines[i] || !isShopDate($0.lowercased()) }
                .joined(separator: " ")
            if let date = firstDate(in: window, now: now) { return (date, type) }
            // "USE BY 14/11" or "14.11" with no year, only on the same line as the words.
            if let date = shortNumericDate(in: lines[i], now: now) { return (date, type) }
        }
        // 2. Any plausible date on its own.
        let skip = ["freeze", "packed", "produced", "opened", "cook", "defrost"]
        for line in lines {
            let lower = line.lowercased()
            if skip.contains(where: { lower.contains($0) }) || isShopDate(lower) { continue }
            if let date = firstDate(in: line, now: now) { return (date, nil) }
        }
        return nil
    }

    /// Day and month with no year, like 14/11 or 14.11. Prices (£4.50) and longer numbers are left out.
    private static let shortNumericPattern = "(?<![\\d£$€.,/\\-])(\\d{1,2})[/.](\\d{1,2})(?![\\d/.\\-])"

    private static func shortNumericDate(in text: String, now: Date) -> Date? {
        for m in matches(shortNumericPattern, in: text) {
            guard m.count >= 3, var day = Int(m[1]), var month = Int(m[2]) else { continue }
            if month > 12 && day <= 12 { swap(&day, &month) }
            if let date = makeDate(day: day, month: month, year: nil, now: now) { return date }
        }
        return nil
    }

    private static func dateType(in lower: String) -> DateType? {
        let squeezed = lower.replacingOccurrences(of: "-", with: " ")
        if squeezed.contains("use by") || squeezed.contains("useby") { return .useBy }
        if squeezed.contains("best before") || squeezed.contains("bestbefore") || squeezed.contains("best by")
            || squeezed.range(of: "\\bbbe\\b", options: .regularExpression) != nil { return .bestBefore }
        return nil
    }

    private static func firstDate(in text: String, now: Date) -> Date? {
        for m in matches(namedMonthPattern, in: text) {
            guard m.count >= 4, let day = Int(m[1]), let month = monthIndex[String(m[2].lowercased().prefix(3))] else { continue }
            if let date = makeDate(day: day, month: month, year: Int(m[3]), now: now) { return date }
        }
        for m in matches(numericPattern, in: text) {
            guard m.count >= 4, var day = Int(m[1]), var month = Int(m[2]), let year = Int(m[3]) else { continue }
            if month > 12 && day <= 12 { swap(&day, &month) }
            if let date = makeDate(day: day, month: month, year: year, now: now) { return date }
        }
        return nil
    }

    private static func makeDate(day: Int, month: Int, year: Int?, now: Date) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        func build(_ y: Int) -> Date? {
            var parts = DateComponents()
            parts.year = y
            parts.month = month
            parts.day = day
            guard let date = calendar.date(from: parts),
                  calendar.component(.day, from: date) == day,
                  calendar.component(.month, from: date) == month else { return nil }
            return date
        }

        var result: Date?
        if let year {
            result = build(year < 100 ? year + 2000 : year)
        } else {
            let thisYear = calendar.component(.year, from: today)
            if let date = build(thisYear) {
                let cutoff = calendar.date(byAdding: .day, value: -45, to: today) ?? today
                result = date < cutoff ? build(thisYear + 1) : date
            }
        }
        // Ignore dates that cannot be an expiry date.
        guard let date = result,
              let earliest = calendar.date(byAdding: .day, value: -60, to: today),
              let latest = calendar.date(byAdding: .year, value: 6, to: today),
              date >= earliest, date <= latest else { return nil }
        return date
    }

    // MARK: Storage

    /// Storage wording on UK labels. Checked in this order, so "once opened keep refrigerated"
    /// on a jar still counts as cupboard until opened.
    private static func findStorage(in lines: [String]) -> Storage? {
        let text = lines.joined(separator: " ").lowercased()
        if text.contains("keep frozen") || text.contains("store frozen") || text.contains("store in a freezer") { return .freezer }
        let cupboard = ["cool, dry place", "cool dry place", "cool and dry", "store in a cupboard", "ambient"]
        if cupboard.contains(where: { text.contains($0) }) { return .cupboard }
        let fridge = ["keep refrigerated", "keep in the fridge", "keep in a fridge", "store in a refrigerator",
                      "store in the fridge", "refrigerate", "keep chilled", "store below 5"]
        if fridge.contains(where: { text.contains($0) }) { return .fridge }
        return nil
    }

    // MARK: Weight and price

    private static func findWeightKg(in lines: [String]) -> Double? {
        let pattern = "\\b(\\d+(?:[.,]\\d+)?)\\s?(kg|g|ml|cl|l|pints?)\\b"
        for line in lines {
            for m in matches(pattern, in: line) {
                guard m.count >= 3, let value = Double(m[1].replacingOccurrences(of: ",", with: ".")) else { continue }
                switch m[2].lowercased() {
                case "kg", "l": return value
                case "g", "ml": return value / 1000
                case "cl": return value / 100
                default: return value * 0.568   // pints
                }
            }
        }
        return nil
    }

    private static func findPrice(in lines: [String]) -> Double? {
        for line in lines {
            for m in matches("£\\s?(\\d+(?:\\.\\d{1,2})?)", in: line) {
                if m.count >= 2, let value = Double(m[1]), value > 0, value < 100 { return value }
            }
        }
        return nil
    }

    // MARK: Matching foods

    private static let optionalWords: Set<String> = ["fresh", "jar", "cooked", "sliced"]

    /// Other names for the same food. Phrase -> preset name.
    private static let aliases: [(phrase: String, preset: String)] = [
        ("semi skimmed", "Milk"), ("skimmed", "Milk"), ("whole milk", "Milk"), ("full fat milk", "Milk"),
        ("oat milk", "Oat drink"), ("oat drink", "Oat drink"), ("oatly", "Oat drink"),
        ("cheddar", "Cheddar cheese"), ("cheese", "Cheddar cheese"),
        ("yogurt", "Natural yoghurt"), ("yoghurt", "Natural yoghurt"), ("skyr", "Natural yoghurt"),
        ("cream", "Double cream"), ("creme fraiche", "Crème fraîche"),
        ("minced beef", "Beef mince"), ("beef mince", "Beef mince"), ("minced pork", "Pork mince"), ("pork mince", "Pork mince"),
        ("rump steak", "Beef steak"), ("sirloin", "Beef steak"), ("ribeye", "Beef steak"), ("fillet steak", "Beef steak"),
        ("pork chop", "Pork chops"), ("gammon", "Sliced ham"), ("ham", "Sliced ham"),
        ("salmon", "Salmon fillets"), ("cod", "Cod fillets"), ("prawn", "Cooked prawns"), ("king prawn", "Cooked prawns"),
        ("mackerel", "Smoked mackerel"), ("tuna", "Tinned tuna"),
        ("clementine", "Easy peelers"), ("satsuma", "Easy peelers"), ("mandarin", "Easy peelers"),
        ("avocado", "Avocados"), ("pitta", "Pitta bread"), ("tortilla", "Tortilla wraps"), ("wrap", "Tortilla wraps"),
        ("bread", "Sliced bread"), ("loaf", "Sliced bread"), ("wholemeal", "Sliced bread"),
        ("pasta", "Dried pasta"), ("spaghetti", "Dried pasta"), ("penne", "Dried pasta"), ("fusilli", "Dried pasta"),
        ("cereal", "Breakfast cereal"), ("cornflakes", "Breakfast cereal"), ("muesli", "Breakfast cereal"),
        ("oats", "Porridge oats"), ("porridge", "Porridge oats"), ("bean", "Baked beans"),
        ("chopped tomato", "Tinned tomatoes"), ("passata", "Tinned tomatoes"),
        ("mayo", "Mayonnaise"), ("pizza", "Chilled pizza"),
        ("spinach", "Baby spinach"), ("salad", "Mixed salad bag"), ("lettuce", "Iceberg lettuce"),
        ("potato", "Potatoes"), ("tomato", "Tomatoes"), ("pepper", "Peppers"),
        ("egg", "Eggs"), ("frozen chip", "Frozen chips"), ("frozen pea", "Frozen peas"), ("frozen fruit", "Frozen berries"),
        ("chilled pizza", "Chilled pizza"), ("houmous", "Hummus")
    ]

    private static func matchPreset(words: Set<String>, presets: [FoodPreset]) -> FoodPreset? {
        guard !words.isEmpty else { return nil }
        var best: (preset: FoodPreset, score: Double)?

        func consider(_ preset: FoodPreset, score: Double) {
            if let current = best {
                if score > current.score || (score == current.score && preset.name.count < current.preset.name.count) {
                    best = (preset, score)
                }
            } else {
                best = (preset, score)
            }
        }

        for preset in presets {
            let all = tokens(preset.name)
            let required = all.filter { !optionalWords.contains($0) }
            let optional = all.filter { optionalWords.contains($0) }
            guard !required.isEmpty, required.allSatisfy({ words.contains($0) }) else { continue }
            consider(preset, score: Double(required.count) + 0.5 * Double(optional.filter { words.contains($0) }.count))
        }

        for alias in aliases {
            let parts = tokens(alias.phrase)
            guard !parts.isEmpty, parts.allSatisfy({ words.contains($0) }),
                  let preset = presets.first(where: { $0.name == alias.preset }) else { continue }
            consider(preset, score: Double(parts.count) - 0.1)
        }
        return best?.preset
    }

    private static func guessCategory(words: Set<String>) -> String? {
        var best: (name: String, hits: Int)?
        for category in CategoryFallback.all {
            let keywords = Set(category.keywords.flatMap { tokens($0) })
            let hits = words.intersection(keywords).count
            if hits > 0, hits > (best?.hits ?? 0) { best = (category.category, hits) }
        }
        return best?.name
    }

    // MARK: Text helpers

    static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return folded
            .split(whereSeparator: { !$0.isLetter })
            .map { stem(String($0)) }
    }

    /// Very small singular form, applied to both the label and the food names so they agree.
    private static func stem(_ word: String) -> String {
        if word == "yogurt" { return "yoghurt" }
        if word == "mayo" { return "mayonnaise" }
        if word == "houmous" { return "hummus" }
        var w = word
        if w.count > 4, w.hasSuffix("ies") {
            w = String(w.dropLast(3)) + "y"
        } else if w.count > 4, w.hasSuffix("ches") || w.hasSuffix("shes") || w.hasSuffix("sses") || w.hasSuffix("xes") {
            w = String(w.dropLast(2))
        } else if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") {
            w = String(w.dropLast(1))
        }
        return w
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }
}

// MARK: - Barcode lookup (Open Food Facts, free, no account)

/// Looks a barcode up on Open Food Facts. Only the barcode number leaves the phone.
enum ProductLookup {
    struct Info {
        var productName: String?
        var names: [String]      // product name, generic name, pack size
        var categoryTags: [String]
    }

    static func info(forBarcode code: String) async -> Info? {
        guard (8...14).contains(code.count), code.allSatisfy({ $0.isNumber }),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,generic_name,quantity,categories_tags")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("PiggyFridge/1.0 (noontidestudio@gmail.com)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any] else { return nil }

        var names: [String] = []
        for key in ["product_name", "generic_name", "quantity"] {
            if let value = product[key] as? String, !value.isEmpty { names.append(value) }
        }
        let tags = (product["categories_tags"] as? [String] ?? []).map {
            $0.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ")
        }
        var title = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces)
        if let t = title, t.isEmpty { title = nil }
        if let t = title, let brand = (product["brands"] as? String)?.split(separator: ",").first.map({ String($0).trimmingCharacters(in: .whitespaces) }),
           !brand.isEmpty, !t.lowercased().contains(brand.lowercased()) {
            title = "\(brand) \(t)"
        }
        return Info(productName: title, names: names, categoryTags: tags)
    }
}
