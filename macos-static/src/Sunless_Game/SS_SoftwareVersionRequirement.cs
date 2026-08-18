using System;
using HarmonyLib;
using Sunless.Game.ApplicationProviders;
using Sunless.Game.Import;
using UnityEngine;

namespace SSTranslator.Sunless_Game;

/// <summary>
/// The original game removes dots and parses the result as one integer. That
/// makes 2.3.0.22 look older than 2.2.4.3141. Use segment comparison only when
/// both values are valid; otherwise let the original method run unchanged.
/// </summary>
[HarmonyPatch(typeof(SoftwareVersionRequirement), nameof(SoftwareVersionRequirement.SoftwareNewEnough))]
internal static class SS_SoftwareVersionRequirement
{
    [HarmonyPrefix]
    private static bool SSPatch_SoftwareNewEnough(
        SoftwareVersionRequirement __instance,
        ref bool __result)
    {
        if (__instance == null || string.IsNullOrEmpty(__instance.SoftwareRequired))
            return true;

        var current = GameProvider.VERSION_NUMBER;
        var required = __instance.SoftwareRequired;
        if (!SS_VersionLogic.TryCompare(current, required, out var comparison))
        {
            Debug.LogWarning(
                "[SSTranslator] Software version parse failed; preserving original game logic. " +
                "current=" + current + ", required=" + required);
            return true;
        }

        __result = comparison >= 0;
        Debug.Log(
            "[SSTranslator] Software version comparison: current=" + current +
            ", required=" + required + ", result=" + __result);
        return false;
    }
}
