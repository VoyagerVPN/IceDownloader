let currentStreams = {};

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'fetch') {
        fetch(request.url, {
            method: request.method || 'GET',
            headers: request.headers || {},
            body: request.data || null
        })
        .then(async response => {
            const status = response.status;
            const text = await response.text();
            sendResponse({ status, responseText: text });
        })
        .catch(err => {
            console.error('Fetch error:', err);
            sendResponse({ status: 0, error: err.toString() });
        });
        return true; 
    }

    if (request.action === 'startEventStream') {
        const { url, streamId } = request;
        
        if (currentStreams[streamId]) {
            currentStreams[streamId].abort();
        }
        
        const controller = new AbortController();
        currentStreams[streamId] = controller;
        
        fetch(url, { signal: controller.signal })
            .then(async (response) => {
                if (!response.body) throw new Error("No response body");
                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let buffer = '';
                
                sendResponse({ success: true }); 
                
                try {
                    while (true) {
                        const { done, value } = await reader.read();
                        if (done) break;
                        
                        buffer += decoder.decode(value, { stream: true });
                        let boundary = buffer.indexOf('\n\n');
                        while (boundary !== -1) {
                            const chunk = buffer.slice(0, boundary).trim();
                            buffer = buffer.slice(boundary + 2);
                            boundary = buffer.indexOf('\n\n');
                            
                            if (chunk.startsWith('data: ')) {
                                const data = chunk.slice(6);
                                chrome.tabs.sendMessage(sender.tab.id, {
                                    action: 'sse_message',
                                    streamId,
                                    data
                                });
                            }
                        }
                    }
                } catch (e) {
                    if (e.name !== 'AbortError') {
                        chrome.tabs.sendMessage(sender.tab.id, { action: 'sse_error', streamId });
                    }
                }
            })
            .catch(e => {
                if (e.name !== 'AbortError') {
                    chrome.tabs.sendMessage(sender.tab.id, { action: 'sse_error', streamId });
                }
            });
            
        return true;
    }

    if (request.action === 'closeEventStream') {
        const { streamId } = request;
        if (currentStreams[streamId]) {
            currentStreams[streamId].abort();
            delete currentStreams[streamId];
        }
        sendResponse({ success: true });
        return true;
    }
});
