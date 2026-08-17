using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Threading;
using HarmonyLib;
using JsonFx.Json;
using Sunless.Game.Data.SNRepositories;
using UnityEngine;
using UnityEngine.UI;

namespace SSTranslator;

/// <summary>
/// Entry point used by the macOS static patch. Sunless.Game.dll calls Init from
/// TitleScreenInit.Start; this removes the need for a BepInEx process hook and
/// runs on every normal launch before the main menu is constructed.
/// </summary>
public static class Bootstrap
{
    private static int state;
    private static Harmony harmony;

    public static void Init()
    {
        if (Interlocked.CompareExchange(ref state, 1, 0) != 0)
            return;

        try
        {
            // The standalone DLL lives in Managed/, while its resources live in
            // the dedicated Managed/SunlessSeaCN directory. The original plugin
            // assumed a BepInEx/plugins sibling, so set both roots explicitly.
            var resourceRoot = Path.Combine(
                Path.GetDirectoryName(typeof(Bootstrap).Assembly.Location),
                "SunlessSeaCN");
            SS_Utility.imagePath = Path.Combine(resourceRoot, "Images");
            SS_Utility.dataPath = Path.Combine(resourceRoot, "Data");
            SS_Utility.LoadAllTextures();
            var dataFile = Path.Combine(SS_Utility.dataPath, "qualities.json");
            var reader = new JsonReader();
            SS_Utility.Name2Id = reader.Read<Dictionary<string, int>>(File.ReadAllText(dataFile));

            var splashImage = GameObject.Find("EAWarning")?.transform;
            if (splashImage != null)
            {
                var oldSprite = splashImage.GetComponent<Image>();
                if (oldSprite != null)
                    oldSprite.sprite = SS_Utility.GetSprite(splashImage, "splash-screen.png");
            }

            harmony = new Harmony("tinygrox.SunlessSeaChineseTranslator.macos-static");
            harmony.PatchAll(typeof(Bootstrap).Assembly);
            var contentProbe = EventRepository.Instance.Get(143942);
            Debug.Log("[SSTranslator] content probe 143942: " +
                (contentProbe == null ? "missing" : contentProbe.Name));
            try
            {
                // Patching Start while it is already running cannot execute its
                // postfix for the current call, so apply the title artwork once.
                SS_TitleScreenInit.SSPatch_Anchors();
            }
            catch (Exception titleException)
            {
                Debug.LogWarning("[SSTranslator] title artwork refresh skipped: " + titleException.Message);
            }
            Debug.Log("[SSTranslator] macOS static bootstrap initialized; Harmony patches applied.");
        }
        catch (Exception exception)
        {
            Debug.LogError("[SSTranslator] macOS static bootstrap failed: " + exception);
        }
    }
}
