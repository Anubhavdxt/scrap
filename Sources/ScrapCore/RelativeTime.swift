import Foundation

/// Short "how long ago" wording for the footer's saved indicator.
public enum RelativeTime {
    public static func text(for date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 { return "just now" }
        if seconds < 45 { return "just now" }
        let minutes = (seconds + 30) / 60
        if minutes < 60 { return minutes <= 1 ? "1 min ago" : "\(minutes) min ago" }
        let hours = (minutes + 30) / 60
        if hours < 24 { return hours == 1 ? "1 hr ago" : "\(hours) hr ago" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = max(2, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 2)
        if days < 7 { return "\(days) days ago" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d yyyy")
        return formatter.string(from: date)
    }
}
