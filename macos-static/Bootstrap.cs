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
/// IntroScript.PlayEAWarning and TitleScreenInit.Start. The first call loads
/// resources and starts a short-lived watcher because the EA warning hierarchy
/// is created after PlayEAWarning begins.
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

            TryApplyEAWarning();
            EAWarningWatcher.StartWatching();

            harmony = new Harmony("tinygrox.SunlessSeaChineseTranslator.macos-static");
            harmony.PatchAll(typeof(Bootstrap).Assembly);
            var contentProbe = EventRepository.Instance.Get(143942);
            Debug.Log("[SSTranslator] content probe 143942: " +
                (contentProbe == null ? "missing" : contentProbe.Name));
            Debug.Log("[SSTranslator] macOS static bootstrap initialized; Harmony patches applied.");
        }
        catch (Exception exception)
        {
            Interlocked.Exchange(ref state, 0);
            Debug.LogError("[SSTranslator] macOS static bootstrap failed: " + exception);
        }
    }

    internal static bool TryApplyEAWarning()
    {
        try
        {
            var image = FindEAWarningImage();
            if (image == null)
                return false;

            var sprite = SS_Utility.GetSprite(image.transform, "splash-screen.png");
            if (sprite == null)
                return false;

            image.sprite = sprite;
            Debug.Log("[SSTranslator] EAWarning localized after hierarchy became available.");
            return true;
        }
        catch (Exception exception)
        {
            Debug.LogError("[SSTranslator] EAWarning localization attempt failed: " + exception);
            return false;
        }
    }

    private static Image FindEAWarningImage()
    {
        var direct = GameObject.Find("EAWarning")?.GetComponentInChildren<Image>(true);
        if (direct != null)
            return direct;

        foreach (var image in Resources.FindObjectsOfTypeAll<Image>())
        {
            if (image == null || image.gameObject == null || !image.gameObject.scene.IsValid())
                continue;

            var current = image.transform;
            while (current != null)
            {
                if (current.name.IndexOf("EAWarning", StringComparison.OrdinalIgnoreCase) >= 0)
                    return image;
                current = current.parent;
            }
        }
        return null;
    }
}

/// <summary>
/// Unity creates the intro warning hierarchy during PlayEAWarning, after the
/// static bootstrap entry point has run. Polling for a few seconds is more
/// reliable than one GameObject.Find at method entry and does not change the
/// game's click or scene flow.
/// </summary>
internal sealed class EAWarningWatcher : MonoBehaviour
{
    private const int MaxFrames = 600;
    private int frames;
    private int nextCheck;

    internal static void StartWatching()
    {
        if (GameObject.Find("[SSTranslator] EAWarningWatcher") != null)
            return;

        var watcher = new GameObject("[SSTranslator] EAWarningWatcher");
        UnityEngine.Object.DontDestroyOnLoad(watcher);
        watcher.AddComponent<EAWarningWatcher>();
    }

    private void Update()
    {
        frames++;
        if (frames < nextCheck)
            return;
        nextCheck = frames + 2;

        if (Bootstrap.TryApplyEAWarning() || frames >= MaxFrames)
        {
            if (frames >= MaxFrames)
                Debug.LogWarning("[SSTranslator] EAWarning hierarchy was not found before the watcher timeout.");
            UnityEngine.Object.Destroy(gameObject);
        }
    }
}
