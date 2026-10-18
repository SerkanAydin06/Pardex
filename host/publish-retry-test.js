"use strict";
// A publish retry that answers after the server was stopped must not bring
// the panel back to "running", must not schedule more retries, and must undo
// the dead address it may have written to online.json.
const assert = require("assert/strict");
const { _test: host } = require("./pardex_host");

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function lateAnswer(succeeds) {
  const calls = [];
  let release;
  host.setPublisher((address) => {
    calls.push(address);
    if (address === "") return Promise.resolve();
    // The retry's PUT hangs until the test lets it finish.
    return new Promise((resolve, reject) => {
      release = () => (succeeds ? resolve() : reject(new Error("fetch failed")));
    });
  });
  host.setRetryDelay(5);
  Object.assign(host.state, { phase: "running", onlineUrl: "wss://old.example", localOnly: false, publishError: "Sunucu adresi yayınlanamadı." });
  host.schedulePublishRetry("wss://old.example");
  await wait(30);
  assert.deepEqual(calls, ["wss://old.example"], "retry should be in flight");
  await host.stopServer();
  assert.equal(host.state.phase, "stopped");
  release();
  await wait(30);
  assert.equal(host.state.phase, "stopped", "late answer must not reopen the panel");
  assert.match(host.state.message, /kapatıldı/);
  await wait(30);
  const retries = calls.filter((address) => address === "wss://old.example").length;
  assert.equal(retries, 1, "no retry after stop");
  return calls;
}

async function run() {
  const afterSuccess = await lateAnswer(true);
  assert.equal(afterSuccess.at(-1), "", "a late successful publish is undone");
  const afterFailure = await lateAnswer(false);
  assert.ok(!afterFailure.includes(""), "nothing to undo when the late publish failed");
  console.log("Host publish retry test passed: late answer after stop keeps the panel stopped and clears the dead address");
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
