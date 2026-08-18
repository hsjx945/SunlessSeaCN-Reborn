using System.Reflection;
using System.Security.Cryptography;
using Mono.Cecil;
using Mono.Cecil.Cil;

internal static class Program
{
    private const string BootstrapNamespace = "SSTranslator";
    private const string BootstrapTypeName = "Bootstrap";
    private const string BootstrapMethodName = "Init";
    private const string IntroTypeName = "IntroScript";
    private const string IntroMethodName = "PlayEAWarning";
    private const string TargetTypeName = "TitleScreenInit";
    private const string TargetMethodName = "Start";

    private sealed record Options(
        string Input,
        string Output,
        string Translation,
        string? ExpectedSha256,
        string? Report);

    private static int Main(string[] args)
    {
        try
        {
            if (args.Length > 0 && args[0] == "--check-closure")
            {
                var closure = CheckClosure(args[1..]);
                Console.WriteLine(closure);
                return 0;
            }

            var options = Parse(args);
            var result = Patch(options);
            Console.WriteLine(result);
            if (options.Report is not null)
                File.WriteAllText(options.Report, result + Environment.NewLine);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("sunlesssea-static-patcher: " + exception.Message);
            return 2;
        }
    }

    private static Options Parse(string[] args)
    {
        string? input = null;
        string? output = null;
        string? translation = null;
        string? expected = null;
        string? report = null;

        for (var i = 0; i < args.Length; i++)
        {
            var option = args[i];
            var value = option switch
            {
                "--input" => Next(args, ref i, option),
                "--output" => Next(args, ref i, option),
                "--translation" => Next(args, ref i, option),
                "--expected-sha256" => Next(args, ref i, option),
                "--report" => Next(args, ref i, option),
                "--help" or "-h" => throw new InvalidOperationException(Usage()),
                _ => throw new InvalidOperationException($"unknown argument: {args[i]}\n{Usage()}"),
            };

            switch (option)
            {
                case "--input": input = value; break;
                case "--output": output = value; break;
                case "--translation": translation = value; break;
                case "--expected-sha256": expected = value; break;
                case "--report": report = value; break;
            }
        }

        if (input is null || output is null || translation is null)
            throw new InvalidOperationException(Usage());

        return new Options(input, output, translation, expected, report);
    }

    private static string Next(string[] args, ref int index, string option)
    {
        if (++index >= args.Length || string.IsNullOrWhiteSpace(args[index]))
            throw new InvalidOperationException($"missing value for {option}\n{Usage()}");
        return args[index];
    }

    private static string Usage() =>
        "usage: --input Sunless.Game.dll --output patched.dll --translation SunlessSeaChineseTranslation.dll [--expected-sha256 HEX] [--report FILE]";

    private static string CheckClosure(string[] args)
    {
        string? root = null;
        string? entry = null;
        for (var i = 0; i < args.Length; i++)
        {
            var option = args[i];
            var value = option switch
            {
                "--root" => Next(args, ref i, option),
                "--entry" => Next(args, ref i, option),
                _ => throw new InvalidOperationException($"unknown closure argument: {option}"),
            };
            if (option == "--root") root = value;
            if (option == "--entry") entry = value;
        }

        if (root is null || entry is null)
            throw new InvalidOperationException("usage: --check-closure --root Managed --entry 0Harmony.dll");

        var rootPath = Path.GetFullPath(root);
        var entryPath = Path.Combine(rootPath, entry);
        EnsureRegularFile(entryPath, "closure entry");
        var queue = new Queue<string>();
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        queue.Enqueue(entryPath);

        while (queue.Count > 0)
        {
            var assemblyPath = queue.Dequeue();
            if (!visited.Add(assemblyPath))
                continue;

            using var assembly = AssemblyDefinition.ReadAssembly(
                assemblyPath,
                new ReaderParameters { ReadSymbols = false });
            foreach (var reference in assembly.MainModule.AssemblyReferences)
            {
                var dependencyPath = Path.Combine(rootPath, reference.Name + ".dll");
                if (File.Exists(dependencyPath))
                {
                    queue.Enqueue(dependencyPath);
                    continue;
                }

                if (!IsFrameworkAssembly(reference.Name))
                    throw new InvalidOperationException(
                        $"missing Managed closure dependency {reference.Name} (required by {Path.GetFileName(assemblyPath)})");
            }
        }

        return $"closure-ok=0Harmony.dll files={string.Join(",", visited.Select(Path.GetFileName).OrderBy(name => name, StringComparer.OrdinalIgnoreCase))}";
    }

    private static bool IsFrameworkAssembly(string name)
    {
        return name == "mscorlib" || name == "netstandard" || name == "System" ||
            name.StartsWith("System.", StringComparison.Ordinal) ||
            name.StartsWith("Microsoft.", StringComparison.Ordinal);
    }

    private static string Patch(Options options)
    {
        var inputPath = Path.GetFullPath(options.Input);
        var outputPath = Path.GetFullPath(options.Output);
        var translationPath = Path.GetFullPath(options.Translation);

        EnsureRegularFile(inputPath, "input");
        EnsureRegularFile(translationPath, "translation");
        if (string.Equals(inputPath, outputPath, StringComparison.Ordinal))
            throw new InvalidOperationException("output must be different from input; this patcher never overwrites the game DLL");

        var inputSha = Sha256(inputPath);
        if (options.ExpectedSha256 is not null &&
            !string.Equals(inputSha, options.ExpectedSha256.Trim(), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"input SHA-256 mismatch: expected {options.ExpectedSha256}, got {inputSha}");

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var readerParameters = new ReaderParameters { ReadSymbols = false, InMemory = true };
        using var target = AssemblyDefinition.ReadAssembly(inputPath, readerParameters);
        using var translation = AssemblyDefinition.ReadAssembly(translationPath, new ReaderParameters { ReadSymbols = false });

        var introMethod = FindTarget(target.MainModule, IntroTypeName, IntroMethodName);
        var titleMethod = FindTarget(target.MainModule, TargetTypeName, TargetMethodName);
        var bootstrapMethod = FindBootstrap(translation.MainModule);
        var importedBootstrap = target.MainModule.ImportReference(bootstrapMethod);
        var introExisting = FindBootstrapCall(introMethod);
        var titleExisting = FindBootstrapCall(titleMethod);
        var introAction = introExisting is null ? "injected" : "already-injected";
        var titleAction = titleExisting is null ? "injected" : "already-injected";
        if (introExisting is null)
            InjectBootstrap(introMethod, importedBootstrap);
        if (titleExisting is null)
            InjectBootstrap(titleMethod, importedBootstrap);
        var action = introAction == "already-injected" && titleAction == "already-injected"
            ? "already-injected"
            : "injected";

        target.Write(outputPath);
        Verify(outputPath, inputSha, action);
        var outputSha = Sha256(outputPath);
        return string.Join(Environment.NewLine, new[]
        {
            $"input={inputPath}",
            $"input-sha256={inputSha}",
            $"input-size={new FileInfo(inputPath).Length}",
            $"target-intro={introMethod.FullName}",
            $"bootstrap-intro-action={introAction}",
            $"target-title={titleMethod.FullName}",
            $"bootstrap-title-action={titleAction}",
            $"bootstrap={bootstrapMethod.FullName}",
            $"action={action}",
            $"output={outputPath}",
            $"output-sha256={outputSha}",
            $"output-size={new FileInfo(outputPath).Length}",
            $"translation-assembly={translation.Name.Name}",
        });
    }

    private static MethodDefinition FindTarget(ModuleDefinition module, string typeName, string methodName)
    {
        var candidates = AllTypes(module.Types)
            .Where(type => type.Name == typeName)
            .SelectMany(type => type.Methods.Where(method => method.Name == methodName))
            .ToList();

        if (candidates.Count != 1)
            throw new InvalidOperationException(
                $"expected exactly one {typeName}.{methodName}, found {candidates.Count}: " +
                string.Join(", ", candidates.Select(candidate => candidate.FullName)));

        var method = candidates[0];
        if (!method.HasBody || method.Parameters.Count != 0)
            throw new InvalidOperationException($"target method has unexpected signature: {method.FullName}");
        return method;
    }

    private static MethodDefinition FindBootstrap(ModuleDefinition module)
    {
        var candidates = AllTypes(module.Types)
            .Where(type => type.Namespace == BootstrapNamespace && type.Name == BootstrapTypeName)
            .SelectMany(type => type.Methods.Where(method => method.Name == BootstrapMethodName))
            .ToList();

        if (candidates.Count != 1)
            throw new InvalidOperationException(
                $"expected exactly one {BootstrapNamespace}.{BootstrapTypeName}.{BootstrapMethodName}, found {candidates.Count}");

        var method = candidates[0];
        if (method.IsStatic == false || method.Parameters.Count != 0 || method.ReturnType.FullName != "System.Void")
            throw new InvalidOperationException($"bootstrap has unexpected signature: {method.FullName}");
        return method;
    }

    private static MethodReference? FindBootstrapCall(MethodDefinition target)
    {
        return target.Body.Instructions
            .Where(instruction => instruction.OpCode == OpCodes.Call || instruction.OpCode == OpCodes.Callvirt)
            .Select(instruction => instruction.Operand as MethodReference)
            .FirstOrDefault(method => method is not null &&
                method.Name == BootstrapMethodName &&
                method.DeclaringType.FullName == $"{BootstrapNamespace}.{BootstrapTypeName}");
    }

    private static void InjectBootstrap(MethodDefinition target, MethodReference bootstrap)
    {
        target.Body.GetILProcessor().InsertBefore(
            target.Body.Instructions[0],
            Instruction.Create(OpCodes.Call, bootstrap));
    }

    private static void Verify(string path, string inputSha, string action)
    {
        using var check = AssemblyDefinition.ReadAssembly(path, new ReaderParameters { ReadSymbols = false });
        VerifyTarget(check.MainModule, IntroTypeName, IntroMethodName);
        VerifyTarget(check.MainModule, TargetTypeName, TargetMethodName);

        // A repeat run may legitimately be byte-identical; the caller already
        // enforces that input and output are different paths.
        _ = inputSha;
        _ = action;
    }

    private static void VerifyTarget(ModuleDefinition module, string typeName, string methodName)
    {
        var target = FindTarget(module, typeName, methodName);
        var calls = target.Body.Instructions.Count(instruction =>
            (instruction.OpCode == OpCodes.Call || instruction.OpCode == OpCodes.Callvirt) &&
            instruction.Operand is MethodReference method &&
            method.Name == BootstrapMethodName &&
            method.DeclaringType.FullName == $"{BootstrapNamespace}.{BootstrapTypeName}");
        if (calls != 1)
            throw new InvalidOperationException($"verification expected exactly one Bootstrap.Init call in {typeName}.{methodName}, found {calls}");
    }

    private static IEnumerable<TypeDefinition> AllTypes(IEnumerable<TypeDefinition> types)
    {
        foreach (var type in types)
        {
            yield return type;
            foreach (var nested in AllTypes(type.NestedTypes))
                yield return nested;
        }
    }

    private static void EnsureRegularFile(string path, string label)
    {
        if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.Directory) != 0)
            throw new InvalidOperationException($"{label} is not a regular file: {path}");
    }

    private static string Sha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }
}
