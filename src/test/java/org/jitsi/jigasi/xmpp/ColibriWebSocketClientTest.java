/*
 * Jigasi, the JItsi GAteway to SIP.
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
package org.jitsi.jigasi.xmpp;

import static org.junit.jupiter.api.Assertions.*;

import org.eclipse.jetty.server.Server;
import org.eclipse.jetty.server.ServerConnector;
import org.eclipse.jetty.server.handler.ContextHandler;
import org.eclipse.jetty.websocket.api.*;
import org.eclipse.jetty.websocket.api.annotations.*;
import org.eclipse.jetty.websocket.server.*;
import org.jitsi.utils.logging2.*;
import org.json.simple.*;
import org.json.simple.parser.*;
import org.junit.jupiter.api.*;

import java.util.concurrent.*;

/**
 * Talks to a real Jetty websocket server that plays the part of JVB's Colibri websocket: it sends a
 * ServerHello when the connection opens and records what the client answers.
 *
 * ColibriWebSocketClient is the fork's own code and was written against the Jetty 11 websocket API; this is
 * what shows it still works on Jetty 12 (the annotation for "connection opened" and the way messages are sent
 * both changed).
 */
public class ColibriWebSocketClientTest
{
    /** The JVB side. */
    @WebSocket
    public static class JvbEndpoint
    {
        final BlockingQueue<String> received = new LinkedBlockingQueue<>();

        final BlockingQueue<Integer> closeCodes = new LinkedBlockingQueue<>();

        @OnWebSocketOpen
        public void onOpen(Session session)
        {
            session.sendText("{\"colibriClass\":\"ServerHello\"}", Callback.NOOP);
        }

        @OnWebSocketMessage
        public void onMessage(String message)
        {
            received.add(message);
        }

        @OnWebSocketClose
        public void onClose(int statusCode, String reason)
        {
            closeCodes.add(statusCode);
        }
    }

    private Server server;

    private JvbEndpoint jvb;

    private String url;

    @BeforeEach
    public void startServer()
        throws Exception
    {
        jvb = new JvbEndpoint();
        server = new Server();
        ServerConnector connector = new ServerConnector(server);
        connector.setPort(0);
        server.addConnector(connector);

        ContextHandler context = new ContextHandler("/");
        WebSocketUpgradeHandler wsHandler = WebSocketUpgradeHandler.from(
            server, context, container -> container.addMapping("/colibri-ws/*", (req, resp, cb) -> jvb));
        context.setHandler(wsHandler);
        server.setHandler(context);
        server.start();

        url = "ws://localhost:" + connector.getLocalPort() + "/colibri-ws/jvb1/conf1/ep1";
    }

    @AfterEach
    public void stopServer()
        throws Exception
    {
        server.stop();
    }

    private static String colibriClass(String json)
        throws ParseException
    {
        assertNotNull(json, "the client did not send the expected message in time");
        return (String) ((JSONObject) new JSONParser().parse(json)).get("colibriClass");
    }

    @Test
    public void answersServerHelloAndReportsConnected()
        throws Exception
    {
        ColibriWebSocketClient client = new ColibriWebSocketClient(url, "ep1", new LoggerImpl("test"));
        CountDownLatch connected = new CountDownLatch(1);
        client.setConnectionListener(new ColibriWebSocketClient.ConnectionListener()
        {
            @Override
            public void onConnected()
            {
                connected.countDown();
            }

            @Override
            public void onDisconnected(int statusCode, String reason)
            {
            }
        });

        try
        {
            assertTrue(client.connect(), "connect() failed");
            assertTrue(connected.await(5, TimeUnit.SECONDS), "never reached the connected state");

            // The handshake order is the contract: ClientHello before ReceiverVideoConstraints.
            assertEquals("ClientHello", colibriClass(jvb.received.poll(5, TimeUnit.SECONDS)));
            String constraints = jvb.received.poll(5, TimeUnit.SECONDS);
            assertEquals("ReceiverVideoConstraints", colibriClass(constraints));
            assertEquals(0L, ((JSONObject) new JSONParser().parse(constraints)).get("lastN"));

            assertTrue(client.isConnected());
        }
        finally
        {
            client.disconnect();
        }
        assertFalse(client.isConnected());

        // Closed with the close handshake (1000), not by dropping the connection (1006).
        assertEquals(StatusCode.NORMAL, jvb.closeCodes.poll(5, TimeUnit.SECONDS));
    }

    @Test
    public void reportsFailureWhenNothingListens()
    {
        // A port that was just released: connect() must return false rather than throw or hang.
        ColibriWebSocketClient client
            = new ColibriWebSocketClient("ws://localhost:1/colibri-ws/x", "ep1", new LoggerImpl("test"));
        assertFalse(client.connect());
        client.disconnect();
    }
}
