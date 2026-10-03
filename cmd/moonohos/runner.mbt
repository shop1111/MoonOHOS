///|
let command_logs : Ref[String?] = Ref(None)

///|
let command_sequence : Ref[Int] = Ref(0)

///|
async fn collect_command(
  exe : String,
  args : Array[String],
  cwd : String,
) -> (Int, String, String) {
  let (out_reader, out_writer) = @process.read_from_process()
  let (err_reader, err_writer) = @process.read_from_process()
  @async.with_task_group() <| group => {
    let process = group.spawn(() => {
      @process.run(
        exe,
        args,
        cwd~,
        stdout=out_writer,
        stderr=err_writer,
        extra_env={ "MOONBIT_NEW_NATIVE": "0" },
        no_console_window=true,
        cancel_handler=@process.hard_cancel(),
      )
    })
    let stdout = group.spawn(() => {
      defer out_reader.close()
      out_reader.read_all().text()
    })
    let stderr = group.spawn(() => {
      defer err_reader.close()
      err_reader.read_all().text()
    })
    (process.wait(), stdout.wait(), stderr.wait())
  }
}

///|
async fn command(
  stage : String,
  exe : String,
  args : Array[String],
  cwd : String,
  timeout_ms? : Int = 300000,
) -> String {
  let started = @async.now()
  command_sequence.val += 1
  let sequence = command_sequence.val
  let (code, stdout, stderr) = @async.with_timeout(
    timeout_ms,
    () => collect_command(exe, args, cwd),
    error=Failure(
      stage +
      ": command timed out after " +
      timeout_ms.to_string() +
      " ms; child process cancelled",
    ),
  ) catch {
    error => {
      if command_logs.val is Some(root) {
        write(
          root + "/" + sequence.to_string() + "-failed.json",
          (
            {
              "stage": stage,
              "exe": exe,
              "args": args.to_json(),
              "status": "failed",
              "elapsedMs": (@async.now() - started).to_string(),
              "error": error.to_string(),
            } : Json).stringify(indent=2),
        )
      }
      match error {
        Failure(_) => raise error
        _ =>
          raise Failure(
            stage + ": cannot execute " + exe + ": " + error.to_string(),
          )
      }
    }
  }
  if command_logs.val is Some(root) {
    write(
      root +
      "/" +
      sequence.to_string() +
      "-" +
      stage.replace_all(old="/", new="_") +
      ".json",
      (
        {
          "stage": stage,
          "exe": exe,
          "args": args.to_json(),
          "exitCode": code,
          "elapsedMs": (@async.now() - started).to_string(),
          "stdout": stdout,
          "stderr": stderr,
        } : Json).stringify(indent=2),
    )
  }
  if code != 0 {
    raise Failure(
      stage + " (exit " + code.to_string() + "):\n" + stdout + stderr,
    )
  }
  stdout
}
