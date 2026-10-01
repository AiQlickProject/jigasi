/*
 * Copyright @ 2026 - present, 8x8 Inc
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.jitsi.jigasi.transcription;

import java.net.*;
import java.nio.charset.*;

/**
 * Builds the URL of the transcriber websocket.
 *
 * The connection id in the path is a random UUID, so on its own it tells the
 * transcription backend nothing about which meeting the audio belongs to. The
 * room is therefore sent as {@code ?room=<room>} (the MUC room JID, e.g.
 * {@code room@conference.domain}), and the backend files the transcript under
 * the meeting with that room name.
 *
 * Kept free of configuration and static state, unlike {@link TranscribeWebsocket},
 * so it can be unit tested without an OSGi container.
 */
final class TranscribeWebsocketUrl
{
    private TranscribeWebsocketUrl()
    {
    }

    /**
     * @param baseUrl the configured websocket URL. It may carry its own query
     * string, which is kept; the connection id goes into the path before it.
     * @param connectionId the connection id appended as the last path segment.
     * @param room the room (MUC JID or plain name), or {@code null}/blank to send none.
     * @return {@code <base path>/<connectionId>[?<base query>][&]room=<room>},
     * with the room URL-encoded.
     */
    static String build(String baseUrl, String connectionId, String room)
    {
        int q = baseUrl.indexOf('?');
        String path = q < 0 ? baseUrl : baseUrl.substring(0, q);
        String query = q < 0 ? "" : baseUrl.substring(q + 1);

        while (path.endsWith("/"))
        {
            path = path.substring(0, path.length() - 1);
        }

        StringBuilder url = new StringBuilder(path).append('/').append(connectionId);
        if (!query.isEmpty())
        {
            url.append('?').append(query);
        }

        if (room != null && !room.trim().isEmpty())
        {
            url.append(query.isEmpty() ? '?' : '&')
                .append("room=")
                .append(URLEncoder.encode(room.trim(), StandardCharsets.UTF_8));
        }

        return url.toString();
    }
}
