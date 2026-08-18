using HarmonyLib;
using Sunless.Game.UI.Components;
using System;
using UnityEngine;

namespace SSTranslator.Sunless_Game;

[HarmonyPatch(typeof(AlertDialog))]
public class SS_AlertDialog
{
    [HarmonyPostfix]
    [HarmonyPatch(MethodType.Constructor, typeof(GameObject), typeof(Action), typeof(string), typeof(string))]
    public static void SSPatch_AlertDialog(GameObject parent, string title, string description)
    {
        SS_Utility.UpdateGameObjectText(parent, "AlertDialog(Clone)/Title", title, TranslateTitle(title));
        SS_Utility.UpdateGameObjectText(parent, "AlertDialog(Clone)/Body", description, TranslateBody(description));
        SS_Utility.UpdateGameObjectText(parent, "AlertDialog(Clone)/Continue/Text", "Continue", "继续");
    }

    private static string TranslateTitle(string title)
    {
        return title switch
        {
            "Warning" => "警告",
            "Fatal Error" => "致命错误",
            "Unable to load save file" => "无法载入存档",
            "Restoring fallback save file" => "正在恢复备用存档",
            _ => title
        };
    }

    private static string TranslateBody(string body)
    {
        if (body == "The maximum recommended resolution is 1920x1080, you may experience issues above this size.")
            return "建议最高分辨率为 1920×1080；使用更高分辨率时可能出现显示问题。";
        if (body == "Cannot connect to the server to retrieve latest news.")
            return "无法连接服务器以获取最新消息。";
        if (body == "There was a problem connecting to the server")
            return "连接服务器时出现问题。";
        if (body == "Connect to our server to retrieve latest news and check for content updates.")
            return "连接服务器以获取最新消息并检查内容更新。";
        if (body == "The import failed, continue with your saved game or try again later.")
            return "导入失败，可以继续游玩已保存的游戏，或稍后重试。";
        if (body == "Backup failed! Please contact support.")
            return "备份存档失败！请联系支持人员。";
        if (body == "Save failed!")
            return "存档失败！";
        if (body == "You must choose a name for your save file.")
            return "你必须为存档选择一个名称。";

        const string prefix = "The save file \"";
        if (body.StartsWith(prefix, StringComparison.Ordinal))
        {
            int suffixIndex = body.IndexOf(".json\"", prefix.Length, StringComparison.Ordinal);
            if (suffixIndex >= 0)
            {
                string filename = body.Substring(prefix.Length, suffixIndex - prefix.Length) + ".json";
                string tail = body.Substring(suffixIndex + ".json\"".Length);
                if (tail == " appears to be corrupt or invalid, however the fallback save file was OK and has been restored.")
                    return $"存档文件“{filename}”似乎已损坏或无效，但备用存档正常，现已恢复。";
                if (tail == " and its fallback appear to be corrupt or invalid. Please select a different save file to load.")
                    return $"存档文件“{filename}”及其备用文件似乎都已损坏或无效。请选择其他存档载入。";
            }
        }
        return body;
    }
}
