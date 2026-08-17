using System.Collections.Generic;
using FailBetter.Core;
using HarmonyLib;
using Sunless.Game.Data.BaseClasses;
using Sunless.Game.Data.SNRepositories;
using UnityEngine;

namespace SSTranslator;

/// <summary>
/// Emits one deterministic content title after the event repository loads. This
/// makes a misplaced or unreadable addon visible in Player.log without touching
/// saves or changing repository data.
/// </summary>
[HarmonyPatch(typeof(EventRepository), nameof(EventRepository.Load))]
internal static class SS_ContentLoadProbe
{
    private const int ProbeEventId = 143942;

    [HarmonyPostfix]
    private static void AfterEventRepositoryLoad(EventRepository __instance)
    {
        try
        {
            var field = AccessTools.Field(typeof(BaseCollectionRepository<int, Event>), "Entities");
            var entities = (Dictionary<int, Event>)field.GetValue(__instance);
            if (entities.TryGetValue(ProbeEventId, out var probeEvent))
                Debug.Log($"[SSTranslator] content probe {ProbeEventId}: {probeEvent.Name}");
            else
                Debug.LogWarning($"[SSTranslator] content probe {ProbeEventId}: missing");
        }
        catch (System.Exception exception)
        {
            Debug.LogWarning("[SSTranslator] content probe failed: " + exception.Message);
        }
    }
}
