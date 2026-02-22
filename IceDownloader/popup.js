const SERVER_URL = 'http://127.0.0.1:3100';

document.addEventListener('DOMContentLoaded', async () => {
    // Initial status check
    checkDaemonStatus();

    // Load settings from storage
    chrome.storage.local.get(['autoStart', 'showTray', 'autoUpdate'], (items) => {
        if (items.autoStart !== undefined) document.getElementById('autoStart').checked = items.autoStart;
        if (items.showTray !== undefined) document.getElementById('showTray').checked = items.showTray;
        if (items.autoUpdate !== undefined) document.getElementById('autoUpdate').checked = items.autoUpdate;
    });

    // Listeners for changes
    ['autoStart', 'showTray', 'autoUpdate'].forEach(id => {
        document.getElementById(id).addEventListener('change', (e) => {
            const val = e.target.checked;
            chrome.storage.local.set({ [id]: val });
            updateDaemonSetting(id, val);
        });
    });

    document.getElementById('openLog').addEventListener('click', () => {
        // Logic to open daemon logs or folder
    });
});

async function checkDaemonStatus() {
    const statusEl = document.getElementById('daemon-status');
    try {
        const res = await fetch(`${SERVER_URL}/status?url=ping`);
        if (res.ok) {
            statusEl.textContent = 'Активна';
            statusEl.style.color = '#4caf50';
        } else {
            throw new Error();
        }
    } catch (e) {
        statusEl.textContent = 'Не запущена';
        statusEl.style.color = '#f44336';
    }
}

async function updateDaemonSetting(key, val) {
    try {
        await fetch(`${SERVER_URL}/config`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ [key]: val })
        });
    } catch (e) {
        console.error('Failed to update daemon setting:', e);
    }
}
