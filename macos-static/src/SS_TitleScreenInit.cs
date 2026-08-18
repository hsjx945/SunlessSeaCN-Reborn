using HarmonyLib;
using System;
using System.Linq;
using System.Text.RegularExpressions;
using UnityEngine;
using UnityEngine.UI;

namespace SSTranslator;

[HarmonyPatch(typeof(Sunless.Game.Scripts.Menus.TitleScreenInit))]
public class SS_TitleScreenInit
{
    [HarmonyPostfix]
    [HarmonyPatch("Start")]
    public static void SSPatch_Anchors()
    {
        var titlePanel = FindTitlePanel();
        if (titlePanel != null)
        {
            TryApplyTitleImage(titlePanel, 0);
            TryApplyTitleImage(titlePanel, 1);
        }
        else
        {
            Debug.LogWarning("[SSTranslator] TitleScreenInit: TitlePanel was not found; continuing with text-only localization.");
        }

        // Keep text localization independent from artwork. Unity throws when
        // a Sprite rect exceeds a replacement texture, so image failures must
        // never prevent the footer labels from being translated.
        try
        {
            ApplyTitleTexts();
        }
        catch (Exception exception)
        {
            Debug.LogError("[SSTranslator] TitleScreenInit: title text localization failed: " + exception);
        }
    }

    private static Transform FindTitlePanel()
    {
        var direct = GameObject.Find("TitlePanel")?.transform;
        if (direct != null)
            return direct;

        foreach (var candidate in Resources.FindObjectsOfTypeAll<Transform>())
        {
            if (candidate == null || candidate.gameObject == null || !candidate.gameObject.scene.IsValid())
                continue;
            if (string.Equals(candidate.gameObject.name, "TitlePanel", StringComparison.OrdinalIgnoreCase))
                return candidate;
        }
        return null;
    }

    private static void TryApplyTitleImage(Transform titlePanel, int index)
    {
        try
        {
            ApplyTitleImage(titlePanel, index);
        }
        catch (Exception exception)
        {
            Debug.LogError($"[SSTranslator] TitleScreenInit: title image {index} localization failed; text localization will continue: {exception}");
        }
    }

    private static void ApplyTitleImage(Transform titlePanel, int index)
    {
        if (titlePanel.childCount <= index)
        {
            Debug.LogWarning($"[SSTranslator] TitleScreenInit: title image child {index} was not found.");
            return;
        }

        Transform child = titlePanel.GetChild(index);
        if (child == null)
            return;

        Image image = child.GetComponent<Image>() ?? child.GetComponentInChildren<Image>(true);
        if (image == null || image.sprite == null)
        {
            Debug.LogWarning($"[SSTranslator] TitleScreenInit: title image child {index} has no Image/Sprite.");
            return;
        }

        // Reuse the existing Chinese title artwork for both panels; the
        // English Zubmariner title asset is deliberately never loaded.
        Texture2D texture = SS_Utility.GetImageTexture2D("Title.png");
        if (texture == null)
        {
            Debug.LogWarning($"[SSTranslator] TitleScreenInit: Chinese title texture is unavailable for child {index}.");
            return;
        }

        var oldSprite = image.sprite;
        var sourceRect = oldSprite.rect;
        var replacementRect = new Rect(0, 0, texture.width, texture.height);
        var sourceWidth = Mathf.Max(1f, sourceRect.width);
        var sourceHeight = Mathf.Max(1f, sourceRect.height);
        var normalizedPivot = new Vector2(
            Mathf.Clamp01(oldSprite.pivot.x / sourceWidth),
            Mathf.Clamp01(oldSprite.pivot.y / sourceHeight));
        var scaleX = texture.width / sourceWidth;
        var scaleY = texture.height / sourceHeight;
        var border = oldSprite.border;
        var left = Mathf.Clamp(border.x * scaleX, 0, texture.width);
        var right = Mathf.Clamp(border.z * scaleX, 0, texture.width - left);
        var bottom = Mathf.Clamp(border.y * scaleY, 0, texture.height);
        var top = Mathf.Clamp(border.w * scaleY, 0, texture.height - bottom);

        var sprite = Sprite.Create(
            texture,
            replacementRect,
            normalizedPivot,
            Mathf.Max(1f, oldSprite.pixelsPerUnit),
            0,
            SpriteMeshType.FullRect,
            new Vector4(left, bottom, right, top));
        image.sprite = sprite;
        Debug.Log($"[SSTranslator] TitleScreenInit: title image {index} localized with texture {texture.width}x{texture.height}.");
    }

    private static void ApplyTitleTexts()
    {
        var sceneTexts = Resources.FindObjectsOfTypeAll<Text>()
            .Where(text => text != null && text.gameObject != null && text.gameObject.scene.IsValid())
            .ToArray();
        var versionCount = 0;
        var supportCount = 0;
        var copyrightCount = 0;

        foreach (var text in sceneTexts)
        {
            var original = text.text ?? string.Empty;
            var trimmed = original.Trim();
            if (IsVersionText(trimmed))
            {
                Match match = Regex.Match(trimmed, @"\d+(?:\.\d+)+");
                string number = match.Success ? match.Value : "2.3.0.22";
                text.text = "无光之海：潜海者 版本 " + number;
                versionCount++;
                continue;
            }

            if (IsSupportText(trimmed))
            {
                // Keep the existing click handler/URL; translate only the
                // visible label or URL text.
                text.text = "支持与帮助（点击打开官网）";
                supportCount++;
                continue;
            }

            if (IsCopyrightText(trimmed))
            {
                text.text = "版权所有：费尔贝特游戏 " + DateTime.Now.Year;
                copyrightCount++;
            }
        }

        Debug.Log($"[SSTranslator] TitleScreenInit: localized title texts version={versionCount}, support={supportCount}, copyright={copyrightCount}.");
    }

    private static bool IsVersionText(string value)
    {
        return Regex.IsMatch(value, @"(?i)(sunless\s+sea|zubmariner).*\d+(?:\.\d+)+");
    }

    private static bool IsSupportText(string value)
    {
        return value.Equals("SUPPORT", StringComparison.OrdinalIgnoreCase) ||
            value.StartsWith("SUPPORT ", StringComparison.OrdinalIgnoreCase) ||
            value.IndexOf("failbettergames.com", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static bool IsCopyrightText(string value)
    {
        return value.IndexOf("Failbetter Games", StringComparison.OrdinalIgnoreCase) >= 0 ||
            Regex.IsMatch(value, @"(?i)©\s*Failbetter");
    }
}
