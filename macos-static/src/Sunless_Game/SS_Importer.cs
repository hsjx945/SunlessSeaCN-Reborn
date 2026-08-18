using HarmonyLib;
using Sunless.Game.Import;
using Sunless.Game.UI.Components;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection.Emit;
using Sunless.Game.ApplicationProviders;
using UnityEngine;

namespace SSTranslator.Sunless_Game;

[HarmonyPatch(typeof(Importer))]
public class SS_Importer
{
    [HarmonyTranspiler]
    [HarmonyPatch(nameof(Importer.CheckIfNewContent))]
    public static IEnumerable<CodeInstruction> SSPatch_CheckIfNewContent(IEnumerable<CodeInstruction> instructions)
    {
        var minValue = AccessTools.Field(typeof(DateTime), nameof(DateTime.MinValue));
        var baseline = AccessTools.Method(typeof(SS_Importer), nameof(GetInitialContentBaseline));
        var patched = false;
        var output = new List<CodeInstruction>();

        foreach (var instruction in instructions)
        {
            if (!patched && instruction.opcode == OpCodes.Ldsfld && Equals(instruction.operand, minValue))
            {
                output.Add(new CodeInstruction(OpCodes.Call, baseline));
                patched = true;
            }
            else
            {
                output.Add(instruction);
            }
        }

        if (!patched)
            Debug.LogWarning("[SSTranslator] Importer.CheckIfNewContent baseline hook was not found; preserving original logic.");
        return output;
    }

    internal static DateTime GetInitialContentBaseline()
    {
        const string gameVersionKey = "GameVersion";
        if (PlayerPrefs.HasKey(gameVersionKey))
            return DateTime.MinValue;

        if (SS_VersionLogic.TryGetBundledBaseline(
                false,
                GameProvider.CONTENT_VERSION_NUMBER,
                out var baseline))
        {
            Debug.Log("[SSTranslator] GameVersion is missing; using bundled content baseline " + baseline.ToString("yyyyMMddHHmm", CultureInfo.InvariantCulture) + ".");
            return baseline;
        }

        Debug.LogWarning("[SSTranslator] Bundled content baseline could not be parsed; preserving original DateTime.MinValue behavior.");
        return DateTime.MinValue;
    }

    [HarmonyTranspiler]
    [HarmonyPatch(nameof(Importer.BeginImport), typeof(IProgressBar), typeof(Action), typeof(Action))]
    public static IEnumerable<CodeInstruction> SSPatch_BeginImport(IEnumerable<CodeInstruction> instructions)
    {
        SS_Utility.PatchHelper(() =>
        {
            SS_Utility.ILReplacer(ref instructions, "Content is up to date", "内容为最新");
        });
        return instructions;
    }
    [HarmonyTranspiler]
    [HarmonyPatch("Download")]
    public static IEnumerable<CodeInstruction> SSPatch_Download(IEnumerable<CodeInstruction> instructions)
    {
        SS_Utility.PatchHelper(() =>
        {
            SS_Utility.ILReplacer(ref instructions, "Downloading...", "正在下载…");
        });
        return instructions;
    }
    [HarmonyTranspiler]
    [HarmonyPatch("DownloadImages")]
    public static IEnumerable<CodeInstruction> SSPatch_DownloadImages(IEnumerable<CodeInstruction> instructions)
    {
        SS_Utility.PatchHelper(() =>
        {
            SS_Utility.ILReplacer(ref instructions, "Downloading Images...", "正在下载图片…");
        });
        return instructions;
    }
    [HarmonyTranspiler]
    [HarmonyPatch("VerifyDownload")]
    public static IEnumerable<CodeInstruction> SSPatch_VerifyDownload(IEnumerable<CodeInstruction> instructions)
    {
        SS_Utility.PatchHelper(() =>
        {
            SS_Utility.ILReplacer(ref instructions, "Verifying download...", "验证下载内容…");
        });
        return instructions;
    }
    [HarmonyTranspiler]
    [HarmonyPatch("Import")]
    public static IEnumerable<CodeInstruction> SSPatch_Import(IEnumerable<CodeInstruction> instructions)
    {
        SS_Utility.PatchHelper(() =>
        {
            SS_Utility.ILReplacer(ref instructions, "Importing...", "正在导入…");
        });
        return instructions;
    }
}
