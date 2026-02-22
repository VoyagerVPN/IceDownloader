(function() {
    'use strict';

    const SERVER_URL = 'http://127.0.0.1:3100';

    // -- Storage & State -- 
    let ytdlpSettings = {
        autoOpen: false,
        embedMeta: true,
        embedSubs: false,
        sponsorBlock: false,
        hideFolder: false,
        videoQuality: 'best'
    };

    function getSetting(key, defaultVal) {
        return ytdlpSettings.hasOwnProperty(key) ? ytdlpSettings[key] : defaultVal;
    }

    function setSetting(key, val) {
        ytdlpSettings[key] = val;
        chrome.storage.local.set({ ['ytdlp_' + key]: val });
    }

    // -- CSS Injection --
    function injectStyles() {
        if (document.getElementById('ytdlp-helper-styles')) return;

        const fontLink = document.createElement('link');
        fontLink.rel = 'stylesheet';
        fontLink.href = 'https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,400,0,0';
        document.head.appendChild(fontLink);

        const style = document.createElement('style');
        style.id = 'ytdlp-helper-styles';
        style.textContent = `
            .ytdlp-progress-bg {
                position: absolute;
                top: 0;
                left: 0;
                height: 100%;
                background-color: currentColor;
                opacity: 0.15;
                z-index: 0;
                pointer-events: none;
                transition: width 0.3s linear;
            }
            .ytdlp-pill-left-content, .yt-spec-button-shape-next__icon {
                position: relative;
                z-index: 1;
            }
            .ytdlp-segmented-buttons-wrapper {
                display: flex;
                flex-direction: row;
                align-items: center;
                height: 36px;
                border-radius: 18px;
                margin-right: 8px;
            }
            .ytdlp-segmented-buttons-wrapper button {
                height: 36px !important;
                box-sizing: border-box !important;
                margin: 0 !important;
            }
            .ytdlp-icon {
                font-family: 'Material Symbols Rounded', sans-serif !important;
                font-size: 20px !important;
                font-weight: normal !important;
                line-height: 1 !important;
                color: currentColor;
                font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
                width: 24px;
                height: 24px;
                margin: 0;
                padding: 0;
            }
            @keyframes ytdlp-spin { 
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); } 
            }
            .ytdlp-spin-icon {
                animation: ytdlp-spin 1s linear infinite;
                display: flex !important;
            }
            .ytdlp-settings-header {
                display: flex;
                align-items: center;
                padding: 8px 16px;
                color: var(--yt-spec-text-secondary);
                font-size: 1.2rem;
                font-weight: 500;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                margin-top: 4px;
            }
        `;
        document.head.appendChild(style);
    }

    // -- UI Components --
    function showToast(message) {
        const toast = document.createElement('div');
        toast.style.position = 'fixed';
        toast.style.bottom = '80px';
        toast.style.left = '32px';
        toast.style.backgroundColor = 'var(--yt-spec-brand-button-background, #cc0000)';
        toast.style.color = 'var(--yt-spec-brand-text-button, white)';
        toast.style.padding = '12px 24px';
        toast.style.borderRadius = '8px';
        toast.style.fontSize = '1.4rem';
        toast.style.fontWeight = '500';
        toast.style.zIndex = '9999';
        toast.style.boxShadow = '0 4px 12px rgba(0,0,0,0.5)';
        toast.style.opacity = '0';
        toast.style.transition = 'opacity 0.3s ease-in-out';
        toast.innerHTML = `<span style="margin-right:8px;vertical-align:middle;">❌</span><span style="vertical-align:middle;">${message}</span>`;
        document.body.appendChild(toast);
        
        setTimeout(() => toast.style.opacity = '1', 10);
        setTimeout(() => {
            toast.style.opacity = '0';
            setTimeout(() => toast.remove(), 300);
        }, 5000);
    }

    function createSettingItem(text, storageKey, defaultVal, callback) {
        const paperItem = document.createElement('tp-yt-paper-item');
        paperItem.className = 'style-scope ytd-menu-popup-renderer ytdlp-settings-item';
        paperItem.setAttribute('role', 'menuitem');
        paperItem.style.cursor = 'pointer';
        paperItem.style.display = 'flex';
        paperItem.style.alignItems = 'center';
        paperItem.style.minHeight = '36px';
        paperItem.style.padding = '0 16px';
        paperItem.style.margin = '0';
        paperItem.style.width = '100%';
        paperItem.style.boxSizing = 'border-box';
        paperItem.style.userSelect = 'none';
        
        const iconSpan = document.createElement('span');
        iconSpan.className = 'ytdlp-icon material-symbols-rounded';
        iconSpan.style.marginRight = '16px';
        iconSpan.style.fontSize = '24px';
        iconSpan.style.color = 'currentColor';
        
        let state = getSetting(storageKey, defaultVal);
        iconSpan.textContent = state ? 'toggle_on' : 'toggle_off';
        
        const textSpan = document.createElement('span');
        textSpan.style.fontSize = '1.4rem';
        textSpan.style.lineHeight = '2rem';
        textSpan.style.flex = '1';
        textSpan.textContent = text;
        
        paperItem.appendChild(iconSpan);
        paperItem.appendChild(textSpan);
        
        paperItem.addEventListener('mouseenter', () => {
            paperItem.style.backgroundColor = 'rgba(128, 128, 128, 0.2)';
        });
        paperItem.addEventListener('mouseleave', () => {
            paperItem.style.backgroundColor = 'transparent';
        });
        
        paperItem.onclick = (e) => {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            
            state = !state;
            setSetting(storageKey, state);
            iconSpan.textContent = state ? 'toggle_on' : 'toggle_off';
            if (callback) callback(state);
            
            return false;
        };
        return paperItem;
    }

    function createQualitySelector() {
        const paperItem = document.createElement('tp-yt-paper-item');
        paperItem.className = 'style-scope ytd-menu-popup-renderer ytdlp-settings-item';
        paperItem.setAttribute('role', 'menuitem');
        paperItem.style.cursor = 'pointer';
        paperItem.style.display = 'flex';
        paperItem.style.alignItems = 'center';
        paperItem.style.minHeight = '36px';
        paperItem.style.padding = '0 16px';
        paperItem.style.margin = '0';
        paperItem.style.width = '100%';
        paperItem.style.boxSizing = 'border-box';
        paperItem.style.userSelect = 'none';
        
        const iconSpan = document.createElement('span');
        iconSpan.className = 'ytdlp-icon material-symbols-rounded';
        iconSpan.style.marginRight = '16px';
        iconSpan.style.fontSize = '24px';
        iconSpan.style.color = 'currentColor';
        iconSpan.textContent = 'high_quality';
        
        const textSpan = document.createElement('span');
        textSpan.style.fontSize = '1.4rem';
        textSpan.style.lineHeight = '2rem';
        textSpan.style.flex = '1';
        textSpan.textContent = 'Качество видео';
        
        const qualitySelect = document.createElement('select');
        qualitySelect.style.appearance = 'none';
        qualitySelect.style.border = 'none';
        qualitySelect.style.backgroundColor = 'transparent';
        qualitySelect.style.color = 'var(--yt-spec-text-secondary)';
        qualitySelect.style.fontSize = '1.3rem';
        qualitySelect.style.paddingRight = '16px';
        qualitySelect.style.cursor = 'pointer';
        qualitySelect.style.outline = 'none';
        qualitySelect.style.backgroundImage = 'url("data:image/svg+xml;charset=US-ASCII,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2218%22%20height%3D%2218%22%20viewBox%3D%220%200%2024%2024%22%20fill%3D%22%23aaaaaa%22%3E%3Cpath%20d%3D%22M7%2010l5%205%205-5z%22%2F%3E%3C%2Fsvg%3E")';
        qualitySelect.style.backgroundRepeat = 'no-repeat';
        qualitySelect.style.backgroundPosition = 'right center';
        
        const opts = ['best|Max', '2160|4K', '1440|1440p', '1080|1080p', '720|720p', '480|480p'];
        opts.forEach(o => {
            const [val, text] = o.split('|');
            const opt = document.createElement('option');
            opt.value = val;
            opt.textContent = text;
            opt.style.backgroundColor = 'var(--yt-spec-brand-background-solid, #0f0f0f)';
            opt.style.color = 'var(--yt-spec-text-primary)';
            if (val === getSetting('videoQuality', 'best')) opt.selected = true;
            qualitySelect.appendChild(opt);
        });
        
        qualitySelect.addEventListener('change', (e) => {
            setSetting('videoQuality', e.target.value);
        });

        qualitySelect.addEventListener('click', (e) => {
            e.stopPropagation();
        });
        
        paperItem.addEventListener('mouseenter', () => {
            paperItem.style.backgroundColor = 'rgba(128, 128, 128, 0.2)';
        });
        paperItem.addEventListener('mouseleave', () => {
            paperItem.style.backgroundColor = 'transparent';
        });
        
        paperItem.appendChild(iconSpan);
        paperItem.appendChild(textSpan);
        paperItem.appendChild(qualitySelect);
        
        return paperItem;
    }

    function injectSettingsMenu(listbox) {
        const sep = document.createElement('div');
        sep.style.height = '1px';
        sep.style.minHeight = '1px';
        sep.style.width = '100%';
        sep.style.display = 'block';
        sep.style.flexShrink = '0';
        sep.style.backgroundColor = 'rgba(128, 128, 128, 0.2)';
        sep.style.margin = '8px 0';
        listbox.appendChild(sep);

        const header = document.createElement('div');
        header.className = 'style-scope ytd-menu-popup-renderer ytdlp-settings-header';
        
        const headerLogo = document.createElement('img');
        headerLogo.src = 'https://thumbs4.imagebam.com/90/4e/2c/ME1AUEF2_t.png';
        headerLogo.style.width = '24px';
        headerLogo.style.height = '24px';
        headerLogo.style.marginRight = '8px';
        headerLogo.style.borderRadius = '4px';
        headerLogo.style.objectFit = 'contain';
        
        const headerText = document.createElement('span');
        headerText.textContent = 'IceDownloader';
        
        header.appendChild(headerLogo);
        header.appendChild(headerText);
        listbox.appendChild(header);

        listbox.appendChild(createQualitySelector());
        listbox.appendChild(createSettingItem('Авто-открытие папки', 'autoOpen', false));
        listbox.appendChild(createSettingItem('Встраивать метаданные', 'embedMeta', true));
        listbox.appendChild(createSettingItem('Встраивать субтитры', 'embedSubs', false));
        listbox.appendChild(createSettingItem('Использовать SponsorBlock', 'sponsorBlock', false));
        listbox.appendChild(createSettingItem('Скрыть кнопку папки', 'hideFolder', false, (hide) => {
            const folderBtn = document.getElementById('ytdlp-folder-btn');
            if (folderBtn) {
                folderBtn.style.display = hide ? 'none' : 'flex';
            }
        }));
    }

    // -- Server Communication (Background Script Proxy) --
    function sendBgRequest(options, callback) {
        chrome.runtime.sendMessage({
            action: 'fetch',
            url: options.url,
            method: options.method,
            headers: options.headers,
            data: options.data
        }, response => {
            if (callback && response) {
                callback(response);
            }
        });
    }

    let currentStreamId = null;

    chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
        if (msg.action === 'sse_message' && msg.streamId === currentStreamId) {
            try {
                const res = JSON.parse(msg.data);
                handleStreamData(res);
            } catch(e) {}
        } else if (msg.action === 'sse_error' && msg.streamId === currentStreamId) {
            chrome.runtime.sendMessage({ action: 'closeEventStream', streamId: currentStreamId });
            currentStreamId = null;
            if (lastUIState) resetUI(...lastUIState);
        }
    });

    let lastUIState = null;

    function handleStreamData(res) {
        if (!lastUIState) return;
        const [url, leftIconEl, leftTextEl, rightIconEl, bgEl] = lastUIState;

        if (res.state === 'downloading') {
            const prog = res.progress;
            if (prog) {
                leftIconEl.parentElement.style.display = 'none';
                leftTextEl.textContent = `${prog.percent}% Загрузка`;
                bgEl.style.width = `${prog.percent}%`;
            } else {
                leftIconEl.parentElement.style.display = '';
                leftIconEl.className = 'ytdlp-icon material-symbols-rounded ytdlp-spin-icon';
                leftIconEl.textContent = 'sync';
                leftTextEl.textContent = 'Анализ';
                bgEl.style.width = '0%';
            }
        } else if (res.state === 'downloaded') {
            chrome.runtime.sendMessage({ action: 'closeEventStream', streamId: currentStreamId });
            currentStreamId = null;
            
            leftIconEl.parentElement.style.display = '';
            leftTextEl.textContent = 'Скачать';
            leftIconEl.className = 'ytdlp-icon material-symbols-rounded';
            leftIconEl.textContent = 'download';
            bgEl.style.width = '0%';
            
            rightIconEl.textContent = 'music_note';
            
            leftIconEl.parentElement.parentElement.onclick = (e) => {
                e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
                startDownload(url, 'video', leftIconEl, leftTextEl, rightIconEl, bgEl);
                return false;
            };

            rightIconEl.parentElement.parentElement.onclick = (e) => {
                e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
                startDownload(url, 'audio', leftIconEl, leftTextEl, rightIconEl, bgEl);
                return false;
            };

            if (getSetting('autoOpen', false)) openFolder(url);

        } else if (res.state === 'error' || res.state === 'none') {
            chrome.runtime.sendMessage({ action: 'closeEventStream', streamId: currentStreamId });
            currentStreamId = null;
            if (res.state === 'error') showToast(res.error || 'Ошибка загрузки');
            resetUI(leftIconEl, leftTextEl, rightIconEl, bgEl, url);
        }
    }

    function startPolling(url, leftIconEl, leftTextEl, rightIconEl, bgEl) {
        if (currentStreamId) {
            chrome.runtime.sendMessage({ action: 'closeEventStream', streamId: currentStreamId });
            currentStreamId = null;
        }
        
        lastUIState = [url, leftIconEl, leftTextEl, rightIconEl, bgEl];
        currentStreamId = 'stream_' + Date.now();
        
        chrome.runtime.sendMessage({
            action: 'startEventStream',
            url: `${SERVER_URL}/status/stream?url=${encodeURIComponent(url)}`,
            streamId: currentStreamId
        });
    }

    function resetUI(leftIconEl, leftTextEl, rightIconEl, bgEl, url) {
        lastUIState = null;
        leftIconEl.parentElement.style.display = '';
        leftIconEl.className = 'ytdlp-icon material-symbols-rounded';
        leftIconEl.textContent = 'download';
        leftTextEl.textContent = 'Скачать';
        bgEl.style.width = '0%';
        
        rightIconEl.textContent = 'music_note';
        
        leftIconEl.parentElement.parentElement.onclick = (e) => {
            e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
            startDownload(url, 'video', leftIconEl, leftTextEl, rightIconEl, bgEl);
            return false;
        };
        
        rightIconEl.parentElement.parentElement.onclick = (e) => {
            e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
            startDownload(url, 'audio', leftIconEl, leftTextEl, rightIconEl, bgEl);
            return false;
        };
    }

    function startDownload(url, format, leftIconEl, leftTextEl, rightIconEl, bgEl) {
        leftIconEl.parentElement.style.display = '';
        leftIconEl.className = 'ytdlp-icon material-symbols-rounded ytdlp-spin-icon';
        leftIconEl.textContent = 'sync';
        leftTextEl.textContent = 'Анализ';
        bgEl.style.width = '0%';
        
        rightIconEl.textContent = 'close';
        rightIconEl.parentElement.parentElement.onclick = (e) => {
            e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
            cancelDownload(url, leftIconEl, leftTextEl, rightIconEl, bgEl);
            return false;
        };

        sendBgRequest({
            method: 'POST',
            url: `${SERVER_URL}/download`,
            headers: { 'Content-Type': 'application/json' },
            data: JSON.stringify({ 
                url: url, 
                format: format,
                sponsorblock: getSetting('sponsorBlock', false),
                embedMetadata: getSetting('embedMeta', true),
                embedSubs: getSetting('embedSubs', false),
                quality: getSetting('videoQuality', 'best')
            })
        }, response => {
            if (response.status === 200 || response.status === 204) {
                startPolling(url, leftIconEl, leftTextEl, rightIconEl, bgEl);
            } else {
                resetUI(leftIconEl, leftTextEl, rightIconEl, bgEl, url);
            }
        });
    }

    function cancelDownload(url, leftIconEl, leftTextEl, rightIconEl, bgEl) {
        if (currentStreamId) {
            chrome.runtime.sendMessage({ action: 'closeEventStream', streamId: currentStreamId });
            currentStreamId = null;
        }
        sendBgRequest({
            method: 'POST',
            url: `${SERVER_URL}/cancel`,
            headers: { 'Content-Type': 'application/json' },
            data: JSON.stringify({ url: url })
        }, () => {
            resetUI(leftIconEl, leftTextEl, rightIconEl, bgEl, url);
        });
        resetUI(leftIconEl, leftTextEl, rightIconEl, bgEl, url);
    }

    function openFolder(url) {
        sendBgRequest({
            method: 'POST',
            url: `${SERVER_URL}/open`,
            headers: { 'Content-Type': 'application/json' },
            data: JSON.stringify({ url: url })
        });
    }

    // -- Button Injection --
    function createButton() {
        const btnContainer = document.createElement('div');
        btnContainer.id = 'ytdlp-helper-btn';
        btnContainer.style.display = 'flex';
        btnContainer.style.alignItems = 'center';

        const folderBtn = document.createElement('button');
        folderBtn.id = 'ytdlp-folder-btn';
        folderBtn.type = 'button';
        folderBtn.className = 'yt-spec-button-shape-next yt-spec-button-shape-next--tonal yt-spec-button-shape-next--mono yt-spec-button-shape-next--size-m yt-spec-button-shape-next--icon-button yt-spec-button-shape-next--enable-backdrop-filter-experiment';
        folderBtn.style.position = 'relative';
        folderBtn.style.marginRight = '8px';
        folderBtn.style.height = '36px'; 
        folderBtn.style.boxSizing = 'border-box';
        folderBtn.style.display = getSetting('hideFolder', false) ? 'none' : 'flex';

        const folderIconWrap = document.createElement('div');
        folderIconWrap.className = 'yt-spec-button-shape-next__icon';
        const folderIcon = document.createElement('span');
        folderIcon.className = 'ytdlp-icon material-symbols-rounded';
        folderIcon.textContent = 'folder';
        folderIconWrap.appendChild(folderIcon);
        folderBtn.appendChild(folderIconWrap);
        
        const dlGroup = document.createElement('div');
        dlGroup.className = 'ytdlp-segmented-buttons-wrapper';
        
        const leftSide = document.createElement('button');
        leftSide.type = 'button';
        leftSide.className = 'yt-spec-button-shape-next yt-spec-button-shape-next--tonal yt-spec-button-shape-next--mono yt-spec-button-shape-next--size-m yt-spec-button-shape-next--icon-leading yt-spec-button-shape-next--segmented-start yt-spec-button-shape-next--enable-backdrop-filter-experiment';
        leftSide.style.position = 'relative';
        leftSide.style.overflow = 'hidden';

        const bgLayer = document.createElement('div');
        bgLayer.className = 'ytdlp-progress-bg';
        bgLayer.style.width = '0%';
        leftSide.appendChild(bgLayer);

        const leftIconWrapper = document.createElement('div');
        leftIconWrapper.className = 'yt-spec-button-shape-next__icon';
        const leftIcon = document.createElement('span');
        leftIcon.className = 'ytdlp-icon material-symbols-rounded';
        leftIcon.textContent = 'download';
        leftIconWrapper.appendChild(leftIcon);
        leftSide.appendChild(leftIconWrapper);

        const leftText = document.createElement('div');
        leftText.className = 'yt-spec-button-shape-next__button-text-content ytdlp-pill-left-content';
        leftText.textContent = 'Скачать';
        leftSide.appendChild(leftText);

        const rightSide = document.createElement('button');
        rightSide.type = 'button';
        rightSide.className = 'yt-spec-button-shape-next yt-spec-button-shape-next--tonal yt-spec-button-shape-next--mono yt-spec-button-shape-next--size-m yt-spec-button-shape-next--icon-button yt-spec-button-shape-next--segmented-end yt-spec-button-shape-next--enable-backdrop-filter-experiment';
        rightSide.style.position = 'relative';

        const rightIconWrapper = document.createElement('div');
        rightIconWrapper.className = 'yt-spec-button-shape-next__icon';
        rightSide.appendChild(rightIconWrapper);
        
        const rightIcon = document.createElement('span');
        rightIcon.className = 'ytdlp-icon material-symbols-rounded';
        rightIcon.textContent = 'music_note';
        rightIconWrapper.appendChild(rightIcon);

        dlGroup.appendChild(leftSide);
        dlGroup.appendChild(rightSide);
        
        btnContainer.appendChild(folderBtn);
        btnContainer.appendChild(dlGroup);

        let currentUrl = window.location.href;
        
        folderBtn.onclick = (e) => {
            e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
            openFolder(currentUrl); return false;
        };

        leftSide.onclick = (e) => {
            e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
            startDownload(currentUrl, 'video', leftIcon, leftText, rightIcon, bgLayer);
            return false;
        };
        
        rightSide.onclick = (e) => {
            e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
            startDownload(currentUrl, 'audio', leftIcon, leftText, rightIcon, bgLayer);
            return false;
        };

        sendBgRequest({ url: `${SERVER_URL}/status?url=${encodeURIComponent(currentUrl)}` }, response => {
            if (response && response.status === 200) {
                try {
                    const res = JSON.parse(response.responseText);
                    if (res.state === 'downloading') {
                        leftIcon.className = 'ytdlp-icon material-symbols-rounded ytdlp-spin-icon';
                        leftIcon.textContent = 'sync';
                        leftText.textContent = 'Анализ';
                        rightIcon.textContent = 'close';
                        rightSide.onclick = (e) => {
                            e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
                            cancelDownload(currentUrl, leftIcon, leftText, rightIcon, bgLayer); return false;
                        };
                        startPolling(currentUrl, leftIcon, leftText, rightIcon, bgLayer);
                    }
                } catch(e) {}
            }
        });

        return btnContainer;
    }

    function injectButton() {
        if (window.location.pathname !== '/watch') return;
        injectStyles();
        if (document.getElementById('ytdlp-helper-btn')) return;

        const actionsContainer = document.querySelector('#top-level-buttons-computed');

        if (actionsContainer && actionsContainer.parentElement) {
            const btn = createButton();
            actionsContainer.parentElement.insertBefore(btn, actionsContainer);
        }
    }

    // -- Initialization & Observers --
    const settingsObserver = new MutationObserver((mutations) => {
        const listbox = document.querySelector('ytd-popup-container tp-yt-paper-listbox#items');
        if (listbox && !listbox.querySelector('.ytdlp-settings-item')) {
            injectSettingsMenu(listbox);
        }
    });

    const bodyObserver = new MutationObserver(() => {
        if (!document.getElementById('ytdlp-helper-btn') && window.location.pathname === '/watch') {
            injectButton();
        }
    });

    window.addEventListener('yt-navigate-finish', () => {
        setTimeout(injectButton, 500);
        setTimeout(injectButton, 2000);
    });

    chrome.storage.local.get(null, (items) => {
        for (const key in items) {
            if (key.startsWith('ytdlp_')) {
                ytdlpSettings[key.replace('ytdlp_', '')] = items[key];
            }
        }
        settingsObserver.observe(document.body, { childList: true, subtree: true });
        bodyObserver.observe(document.body, { childList: true, subtree: true });
        if (window.location.pathname === '/watch') injectButton();
    });

})();
