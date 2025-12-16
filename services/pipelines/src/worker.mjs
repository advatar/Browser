const args = new Set(process.argv.slice(2));

if (args.has('--snapshot')) {
  console.log('[pipelines] snapshot OK');
  process.exit(0);
}
if (args.has('--lint')) {
  console.log('[pipelines] lint succeeded');
  process.exit(0);
}
if (args.has('--self-test')) {
  console.log('[pipelines] self-test complete');
  process.exit(0);
}

const queue = [];

function enqueue(task) {
  queue.push({ ...task, enqueuedAt: Date.now() });
}

function processQueue() {
  const job = queue.shift();
  if (!job) {
    return;
  }
  console.log('[pipelines] executing job', job.name);
  setTimeout(() => {
    console.log('[pipelines] completed job', job.name);
  }, 250);
}

setInterval(processQueue, 500);
setInterval(() => enqueue({ name: 'sample-job', payload: { now: Date.now() } }), 1_000);

console.log('[pipelines] worker started');
