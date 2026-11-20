const send = request => window.webkit.messageHandlers.studyApp.postMessage(request);
const values = new Map(Object.entries(snapshot));
let pending = Promise.resolve(true);
let unsaved = new Map();

function persist(key, value) {
  unsaved.set(key, value);
  pending = pending.then(async () => {
    try {
      await send({action:'save', key, value});
      if (unsaved.get(key) === value) unsaved.delete(key);
      return true;
    } catch (error) {
      window.dispatchEvent(new CustomEvent('study-storage-error', {detail:String(error)}));
      return false;
    }
  });
}

window.crNative = {
  storage: {
    getItem: key => values.get(key) ?? null,
    setItem(key, value) {
      const text = String(value);
      values.set(key, text);
      persist(key, text);
    },
    removeItem(key) {
      values.delete(key);
      persist(key, null);
    }
  },
  async flush() {
    await pending;
    for (const [key, value] of unsaved) persist(key, value);
    await pending;
    return unsaved.size === 0;
  },
  speak: text => send({action:'speak', text}),
  stopSpeech: () => send({action:'stopSpeech'}),
  exportBackup: (data, name) => send({action:'export', data, name}),
  importBackup: () => send({action:'import'})
};
