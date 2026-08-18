using System;
using System.Globalization;

namespace SSTranslator;

/// <summary>
/// Pure version and content-baseline logic shared by the runtime patches and
/// the deterministic regression harness. It deliberately does not decide what
/// to do when parsing fails: callers must preserve the game's original path.
/// </summary>
public static class SS_VersionLogic
{
    public static bool TryCompare(string current, string required, out int comparison)
    {
        comparison = 0;
        if (!TryNormalize(current, out var currentParts) ||
            !TryNormalize(required, out var requiredParts))
            return false;

        var count = Math.Max(currentParts.Length, requiredParts.Length);
        for (var index = 0; index < count; index++)
        {
            var currentPart = index < currentParts.Length ? currentParts[index] : "0";
            var requiredPart = index < requiredParts.Length ? requiredParts[index] : "0";
            if (currentPart.Length != requiredPart.Length)
            {
                comparison = currentPart.Length < requiredPart.Length ? -1 : 1;
                return true;
            }

            var partComparison = string.CompareOrdinal(currentPart, requiredPart);
            if (partComparison != 0)
            {
                comparison = partComparison < 0 ? -1 : 1;
                return true;
            }
        }

        return true;
    }

    /// <summary>
    /// Returns a bundled content date only when the GameVersion key is absent.
    /// A present key, including an invalid one, must remain on the game's
    /// original parsing path; therefore this method returns false for it.
    /// </summary>
    public static bool TryGetBundledBaseline(
        bool hasGameVersionKey,
        string bundledVersion,
        out DateTime baseline)
    {
        baseline = DateTime.MinValue;
        if (hasGameVersionKey || string.IsNullOrWhiteSpace(bundledVersion))
            return false;

        return DateTime.TryParseExact(
            bundledVersion.Trim(),
            "yyyyMMddHHmm",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out baseline);
    }

    private static bool TryNormalize(string value, out string[] parts)
    {
        parts = Array.Empty<string>();
        if (value == null)
            return false;

        var normalized = value.Trim();
        if (normalized.Length == 0)
            return false;

        if (normalized[0] == 'v' || normalized[0] == 'V')
            normalized = normalized.Substring(1);
        if (normalized.Length == 0)
            return false;

        var rawParts = normalized.Split('.');
        var result = new string[rawParts.Length];
        for (var index = 0; index < rawParts.Length; index++)
        {
            var part = rawParts[index];
            if (part.Length == 0)
                return false;
            for (var charIndex = 0; charIndex < part.Length; charIndex++)
            {
                if (part[charIndex] < '0' || part[charIndex] > '9')
                    return false;
            }

            var firstNonZero = 0;
            while (firstNonZero < part.Length - 1 && part[firstNonZero] == '0')
                firstNonZero++;
            result[index] = part.Substring(firstNonZero);
        }

        parts = result;
        return true;
    }
}
