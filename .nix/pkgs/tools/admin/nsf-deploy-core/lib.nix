
{ lib
, writeShellScript
, runCommand
, coreutils
, makeWrapper
, jq
, nsf-data-deploy-tools
}:

let
  toAsbPath = fn:
    assert builtins.isPath fn || builtins.isString fn;
    if builtins.isPath fn then fn else
      if lib.strings.hasPrefix "/" fn then (/. + fn)
        else abort "Expected an absolute path but instead received: '${fn}'.";

  resolveAsbFilepath = bundleDir: fn:
    assert builtins.isPath bundleDir;
    assert builtins.isPath fn || builtins.isString fn;
    if builtins.isPath fn then fn else
      if lib.strings.hasPrefix "/" fn then (/. + fn)
        else (bundleDir + "/${fn}");

  flattenRules = loadedRules:
    let
      rulesFillMissing = x: x // {
        permission = if x ? permission then x.permission else null;
        option = if x ? option && x.option != null then x.option else {};
      };
      rulesListFillMissing = xs:
        builtins.map rulesFillMissing xs;
      rulesAttr2List = x:
        lib.attrsets.mapAttrsToList (k: v:
          rulesFillMissing (v // {
            target = k;
          })
        ) x;

    in
      # Support both attrset rules and list rules.
      if lib.isList loadedRules
        then rulesListFillMissing loadedRules
        else rulesAttr2List loadedRules;

  getBundleDefaultImports = bundleDir:
      bOpts@{ defaultImportsFn }:
    # defaultImportsFn bundleDir;
    lib.lists.forEach (defaultImportsFn bundleDir)(x:
    if builtins.isAttrs x
      then assert x ? path
            || builtins.trace "Missing 'path' attribute on default imports for '${toString bundleDir}'!";
        x // {
          path = toAsbPath x.path;
          default-import = true;
        }
      else {
        path = toAsbPath x;
        allow-inexistent = true;
        default-import = true;
    });


  getBundleImports = bundleDir: bundle: bOpts:
    # TODO: Consider how to allow having an explicit import listing
    #       which allows to explicitly defer to default imports.
    #
    #       IDEA: Could be by specifying a attrset instead of a
    #             path / string which would allow special options.
    #             `{ path = null, default-imports = true}`.
    #
    #             Could be by using some template expension scheme
    #             within the string: `"${default-imports}"`.
    #
    #             Could be by using `null` as a sentinel value for
    #             this purpose.
    #
    #       For the moment, when an explicit import list is
    #       provided, it will be the reponsability of the importer
    #       to import or not the import what would have been default
    #       imported.
    if bundle ? imports
      then bundle.imports
      else getBundleDefaultImports bundleDir bOpts;

  mkDefaultBundle = bundleDir: bOpts: {
    bundleDir = toAsbPath bundleDir;
    imports = getBundleDefaultImports bundleDir bOpts;
  };

  loadDeployFileAt = absFn: bOpts:
    let
      fnCwd = builtins.dirOf absFn;
      rawBundle = builtins.fromJSON (builtins.readFile "${absFn}");
    in
      rawBundle // {
        bundleDir = fnCwd;
        imports = getBundleImports fnCwd rawBundle bOpts;
      };

  resolveDataDeployFilename = bundleDir:
    resolveAsbFilepath bundleDir "./deploy.json";

  getImportPath = importDirective:
    if builtins.isAttrs importDirective
      then importDirective.path
    else if builtins.isPath importDirective || builtins.isString importDirective
      then importDirective
    else abort "Unexpected import directive type: '${builtins.typeOf importDirective}'!";

  allowInexistantImport = importDirective:
    if ! builtins.isAttrs importDirective
      then false
    else if importDirective ? allow-inexistent && importDirective.allow-inexistent
      then true
    else false;

  loadBundleImports = bundleDir: importedPaths: bOpts:
    lib.lists.forEach importedPaths (x:
      let
        relDataPath = getImportPath x;
        absDataPath = resolveAsbFilepath bundleDir relDataPath;
      in
        if allowInexistantImport x
          then loadOptDataDeployBundleOrDefault absDataPath bOpts
          else loadDataDeployBundle absDataPath bOpts
    );

  loadDataDeployBundle = bundleDir: bOpts:
    let
      absFn = resolveDataDeployFilename bundleDir;
    in
      loadDeployFileAt absFn bOpts;

  loadOptDataDeployBundleOrDefault = bundleDir: bOpts:
    let
      absFn = resolveDataDeployFilename bundleDir;
    in
      if builtins.pathExists absFn
        then loadDeployFileAt absFn bOpts
        else mkDefaultBundle bundleDir bOpts;

  loadUnresolvedBundleListFrom = bundleDir: searchPaths: d: bOpts:
    let
      imports = getBundleImports bundleDir d bOpts;
      ds =
        if 0 == builtins.length imports
          then []
          else loadBundleImports bundleDir imports bOpts;
      rs = if d ? rules then (flattenRules d.rules) else [];
      accFn = acc: subD:
        acc ++ loadUnresolvedBundleListFrom
          subD.bundleDir (searchPaths ++ [subD.bundleDir]) subD bOpts;
    in
      (builtins.foldl' accFn [] ds) ++ [{
        inherit bundleDir searchPaths;
        rules = rs;
      }];

  loadUnresolvedBundleListFromOpt = bundleDir: searchPaths: d: bOpts:
    if null == d
      then []
      else loadUnresolvedBundleListFrom bundleDir searchPaths d bOpts;

  loadDataDeployUnresolvedBundleList = bundleDir: searchPaths: bOpts:
      loadUnresolvedBundleListFrom bundleDir searchPaths (
        loadDataDeployBundle bundleDir) bOpts;

  loadOptDataDeployUnresolvedBundleList = bundleDir: searchPaths: bOpts:
      loadUnresolvedBundleListFrom bundleDir searchPaths (
        loadOptDataDeployBundleOrDefault bundleDir bOpts) bOpts;

  resolveMatchingSourceFiles = source: searchPaths:
    let
      accFn = acc: d: let
          p = resolveAsbFilepath d source;
        in if builtins.pathExists p then acc ++ [p] else acc;
      matches = builtins.foldl' accFn [] searchPaths;
    in
      matches;

  flattenDataDeployBundleList = loadedBundleList:
    assert builtins.isList loadedBundleList;
    let
      extendRulesWithBundleInfo = x:
        assert builtins.isAttrs x;
        assert builtins.isList x.rules;
        lib.lists.forEach x.rules (r:
          r // {
            inherit (x) bundleDir searchPaths;
          }
        );
    in {
      rules = lib.lists.flatten (
        builtins.map extendRulesWithBundleInfo loadedBundleList);
    };

  filterOutPropagatedBundleAttrsFromRule = rule:
    lib.attrsets.filterAttrs (k: v:
        !(k == "bundleDir" || k == "searchPaths")) rule;

  # Filter out artificial attrs introduced by `flattenDataDeployBundleList`,
  # namely: `bundleDir` and `searchPaths`.
  filterOutPropagatedBundleAttrsFromFlatRules = flatRules:
      lib.lists.forEach flatRules filterOutPropagatedBundleAttrsFromRule;

  assertOptsWPropagatedBundleAttrs = {
    ruleAdditionalAttrs = {
        # Those are the attrs which are propagated from the bundle to
        # the individual rules when *flattened*. See
        # `flattenDataDeployBundleList`.
        "bundleDir" = null;
        "searchPaths" = null;
    };
  };

  assertOptsDefaults = {
    # By default, struct checking applied.
    ruleAdditionalAttrs = {};
  };

  assertValidRuleTypeImpl =
    validRuleTypes: rule:
      if validRuleTypes ? "${rule.type}"
        then rule
      else
        builtins.abort "Unknown rule type: ${rule.type}!";

  assertValidRuleSchemaImpl =
    validRuleTypes: rsOpts@{ ruleAdditionalAttrs }: rule:
      # TODO: Actual validation of rules're schema after type validation.
      assertValidRuleTypeImpl validRuleTypes rule;

  assertValidRulesSchemaImpl = perRuleTypeSchema: rsOpts: unresolvedFlatRules:
    let
      assertFn = rule:
        assertValidRuleSchemaImpl perRuleTypeSchema rsOpts rule;
    in
      builtins.map assertFn unresolvedFlatRules;

  prettyPrintSearchPaths = xs:
    lib.strings.concatStringsSep "\n" (
      builtins.map (x: "\"${builtins.toString x}\"") xs);

  resolveSourceFile = source: searchPaths: rOpts:
    let
      matches = resolveMatchingSourceFiles source searchPaths;
    in
      if builtins.length matches >= 1
        then builtins.head matches
        else if rOpts ? allow-inexistant-source && rOpts.allow-inexistant-source
          then null
          else builtins.abort ''
            Cannot find source file "${source}" looking in
            the following search paths:
            ${prettyPrintSearchPaths searchPaths}.
          '';

  resolveSourceFiles = sources: searchPaths: rOpts:
    map (src: resolveSourceFile src searchPaths rOpts) sources;

  # Filter out any option that were already processed by `resolveSourceFile`
  # at source resolving time.
  filterOutSourceResolverOptions = flatRules:
    lib.lists.forEach flatRules (x: x // {
      option = lib.attrsets.filterAttrs (
        k: v: k != "allow-inexistant-source") x.option;
    });

  writeNixSrcVersionJson = srcName: version: runCommand
      "${srcName}-version.json"
      { buildInputs = [ jq ]; } ''
    unformatedVersion="${builtins.toFile "unformatted-version" (builtins.toJSON version)}"
    cat "$unformatedVersion" | jq '.' > "$out"
  '';

  writeToPrettyJson = basename: x: let
    unformatedVersion = builtins.toFile basename (
      builtins.toJSON x);
    in
      runCommand basename {
          buildInputs = [ jq ];
        } ''
        cat "${unformatedVersion}" | jq '.' > "$out"
      '';

in

rec {
  inherit loadDataDeployBundle loadOptDataDeployBundleOrDefault;
  inherit loadDataDeployUnresolvedBundleList loadOptDataDeployUnresolvedBundleList;
  inherit flattenDataDeployBundleList filterOutPropagatedBundleAttrsFromRule;
  inherit filterOutPropagatedBundleAttrsFromFlatRules;
  inherit assertOptsWPropagatedBundleAttrs assertOptsDefaults;
  inherit assertValidRuleTypeImpl assertValidRuleSchemaImpl assertValidRulesSchemaImpl;
  inherit resolveSourceFile resolveSourceFiles filterOutSourceResolverOptions;
  inherit writeToPrettyJson;

}
