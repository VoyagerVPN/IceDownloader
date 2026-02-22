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
        window.location.href = 'icedownloader://logs';
    });

    document.getElementById('status-card').addEventListener('click', () => {
        const statusEl = document.getElementById('daemon-status');
        if (statusEl.textContent === 'Не запущена') {
            statusEl.textContent = 'Запуск...';
            statusEl.style.color = '#ff9800';
            window.location.href = 'icedownloader://start';
            
            let checks = 0;
            const interval = setInterval(() => {
                checkDaemonStatus();
                checks++;
                if (checks > 10) clearInterval(interval);
            }, 1000);
        }
    });
});

async function checkDaemonStatus() {
    const statusEl = document.getElementById('daemon-status');
    const cardEl = document.getElementById('status-card');
    try {
        const res = await fetch(`${SERVER_URL}/status?url=ping`);
        if (res.ok) {
            statusEl.textContent = 'Активна';
            statusEl.style.color = '#4caf50';
            cardEl.classList.remove('clickable');
            cardEl.title = "";
        } else {
            throw new Error();
        }
    } catch (e) {
        if (statusEl.textContent !== 'Запуск...') {
            statusEl.textContent = 'Не запущена';
            statusEl.style.color = '#f44336';
            cardEl.classList.add('clickable');
            cardEl.title = "Нажмите, чтобы запустить службу";
        }
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
