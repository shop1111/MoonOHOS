///|
pub struct BuildStage {
  id : String
  description : String
  dependencies : Array[String]
  abi : String?
  outputs : Array[String]
}

///|
fn stage(
  id : String,
  description : String,
  dependencies : Array[String],
  outputs : Array[String],
  abi? : String? = None,
) -> BuildStage {
  { id, description, dependencies, outputs, abi, }
}

///|
pub fn BuildStage::to_json(self : BuildStage) -> Json {
  {
    "id": self.id,
    "description": self.description,
    "dependencies": self.dependencies.to_json(),
    "abi": self.abi.to_json(),
    "outputs": self.outputs.to_json(),
  }
}

///|
pub fn build_stages(
  project : Project,
  abis : Array[String],
) -> Array[BuildStage] raise ConfigError {
  project.validate()
  parse_abis(abis.join(",")) |> ignore
  let stages = [
    stage("environment", "Verify pinned compiler, runtime and SDK", [], []),
    stage(
      "stage",
      "Copy source into an isolated build directory",
      ["environment"],
      ["module/"],
    ),
    stage(
      "interface",
      "Parse declarations and verify manifest signatures",
      ["stage"],
      ["interface.json"],
    ),
    stage(
      "generate",
      "Generate opaque adapters and wrapper package",
      ["interface"],
      ["native/", "module/moonohos_bridge/"],
    ),
    stage(
      "compile",
      "Execute necessary moonc operations as argument arrays",
      ["generate"],
      ["native/core.c"],
    ),
  ]
  let inspections : Array[String] = []
  for abi in abis {
    let configure = "configure/" + abi
    let link = "link/" + abi
    let inspect = "elf/" + abi
    let library = "libs/" + abi + "/lib" + project.native_module + ".so"
    stages.push(
      stage(
        configure,
        "Configure HarmonyOS CMake",
        ["compile"],
        ["cmake-" + abi + "/"],
        abi=Some(abi),
      ),
    )
    stages.push(
      stage(
        link,
        "Link MoonBit runtime and Node-API",
        [configure],
        [library],
        abi=Some(abi),
      ),
    )
    stages.push(
      stage(
        inspect,
        "Verify target architecture, symbols and dependencies",
        [link],
        [],
        abi=Some(abi),
      ),
    )
    inspections.push(inspect)
  }
  stages.push(
    stage("package", "Write types, notices and content manifest", inspections, [
      "manifest.json", "types/", "cmake/",
    ]),
  )
  stages.push(
    stage(
      "verify",
      "Validate complete distribution before publishing",
      ["package"],
      [],
    ),
  )
  stages.push(
    stage(
      "publish",
      "Move complete package into the new output directory",
      ["verify"],
      ["dist/"],
    ),
  )
  validate_stages(stages)
  stages
}

///|
pub fn validate_stages(stages : Array[BuildStage]) -> Unit raise ConfigError {
  let completed : Map[String, Bool] = Map([])
  for stage in stages {
    if stage.id == "" || completed.contains(stage.id) {
      raise Invalid("plan: duplicate or empty stage " + stage.id)
    }
    let seen : Map[String, Bool] = Map([])
    for dependency in stage.dependencies {
      if !completed.contains(dependency) {
        raise Invalid(
          "plan: dependency must precede " + stage.id + ": " + dependency,
        )
      }
      if seen.contains(dependency) {
        raise Invalid("plan: duplicate dependency " + dependency)
      }
      seen[dependency] = true
    }
    completed[stage.id] = true
  }
}

///|
pub fn Project::build_plan(
  self : Project,
  abis : Array[String],
) -> Json raise ConfigError {
  {
    "schema": "moonohos-plan-v1",
    "interface": self.summary(),
    "generation": self.generation_plan(),
    "stages": build_stages(self, abis).map(s => s.to_json()).to_json(),
    "commandTimeoutSeconds": 300,
    "runtime": "not_run",
  }
}
