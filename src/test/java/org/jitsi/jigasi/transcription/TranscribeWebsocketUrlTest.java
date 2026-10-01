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

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.*;

/**
 * The transcriber connects with a random UUID in the path, so the room in
 * {@code ?room=} is the only thing that ties the connection to its meeting.
 */
public class TranscribeWebsocketUrlTest
{
    private static final String BASE = "wss://api.aiqlick.com/transcription/ws";

    private static final String ID = "6f1c2a5e-8d7b-4c1e-9a3f-2b4d6e8f0a1c";

    @Test
    public void testAppendsTheRoomJidUrlEncoded()
    {
        assertEquals(
            BASE + "/" + ID + "?room=aiqlick-interview-abc123%40conference.meet.aiqlick.com",
            TranscribeWebsocketUrl.build(
                BASE, ID, "aiqlick-interview-abc123@conference.meet.aiqlick.com"));
    }

    @Test
    public void testAppendsAPlainRoomName()
    {
        assertEquals(
            BASE + "/" + ID + "?room=aiqlick-interview-abc123",
            TranscribeWebsocketUrl.build(BASE, ID, "aiqlick-interview-abc123"));
    }

    @Test
    public void testNoRoomKeepsTheOldUrl()
    {
        assertEquals(BASE + "/" + ID, TranscribeWebsocketUrl.build(BASE, ID, null));
        assertEquals(BASE + "/" + ID, TranscribeWebsocketUrl.build(BASE, ID, ""));
        assertEquals(BASE + "/" + ID, TranscribeWebsocketUrl.build(BASE, ID, "   "));
    }

    @Test
    public void testEncodesCharactersThatWouldBreakTheQuery()
    {
        assertEquals(
            BASE + "/" + ID + "?room=a%26token%3Dx%23f+g",
            TranscribeWebsocketUrl.build(BASE, ID, "a&token=x#f g"));
    }

    @Test
    public void testKeepsAQueryAlreadyInTheConfiguredUrl()
    {
        assertEquals(
            BASE + "/" + ID + "?region=eu&room=r%40conference.x",
            TranscribeWebsocketUrl.build(BASE + "?region=eu", ID, "r@conference.x"));
        assertEquals(
            BASE + "/" + ID + "?region=eu",
            TranscribeWebsocketUrl.build(BASE + "/?region=eu", ID, null));
    }
}
