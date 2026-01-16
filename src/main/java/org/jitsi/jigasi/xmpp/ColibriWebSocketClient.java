/*
 * Jigasi, the JItsi GAteway to SIP.
 *
 * Copyright @ 2024 8x8, Inc.
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

import org.eclipse.jetty.websocket.api.*;
import org.eclipse.jetty.websocket.api.annotations.*;
import org.eclipse.jetty.websocket.client.*;
import org.jitsi.utils.logging2.*;
import org.json.simple.*;
import org.json.simple.parser.*;

import java.net.*;
import java.util.concurrent.*;

/**
 * Colibri WebSocket client for EndpointMessageTransport communication with JVB.
 * This establishes the data channel that JVB requires for audio forwarding decisions.
 *
 * The Colibri WebSocket protocol uses JSON messages for:
 * - ServerHello: Sent by JVB when connection is established
 * - ClientHello: Sent by client in response to ServerHello
 * - EndpointMessage: Various control messages (dominant speaker, etc.)
 * - PinnedEndpointsChangedEvent: Video pinning
 * - SelectedEndpointsChangedEvent: Video selection
 * - ReceiverVideoConstraints: Video quality constraints
 */
@WebSocket
public class ColibriWebSocketClient
{
    /**
     * The logger.
     */
    private final Logger logger;

    /**
     * The WebSocket URL to connect to (from JVB's Colibri2 response).
     */
    private final String websocketUrl;

    /**
     * The endpoint ID for this Jigasi instance.
     */
    private final String endpointId;

    /**
     * The WebSocket client.
     */
    private WebSocketClient wsClient;

    /**
     * The active WebSocket session.
     */
    private Session wsSession;

    /**
     * Whether the connection is established and ready.
     */
    private volatile boolean connected = false;

    /**
     * JSON parser for incoming messages.
     */
    private final JSONParser jsonParser = new JSONParser();

    /**
     * Connection timeout in milliseconds.
     */
    private static final long CONNECTION_TIMEOUT_MS = 10000L;

    /**
     * Listener for connection state changes.
     */
    private ConnectionListener connectionListener;

    /**
     * Creates a new Colibri WebSocket client.
     *
     * @param websocketUrl The WebSocket URL from JVB's Colibri2 response
     * @param endpointId The endpoint ID for this Jigasi instance
     * @param parentLogger The parent logger
     */
    public ColibriWebSocketClient(String websocketUrl, String endpointId, Logger parentLogger)
    {
        this.websocketUrl = websocketUrl;
        this.endpointId = endpointId;
        this.logger = parentLogger.createChildLogger(ColibriWebSocketClient.class.getName());
    }

    /**
     * Sets the connection listener.
     *
     * @param listener The listener to notify on connection state changes
     */
    public void setConnectionListener(ConnectionListener listener)
    {
        this.connectionListener = listener;
    }

    /**
     * Connects to the Colibri WebSocket.
     *
     * @return true if connection was successful
     */
    public boolean connect()
    {
        if (websocketUrl == null || websocketUrl.isEmpty())
        {
            logger.warn("No Colibri WebSocket URL provided, cannot connect");
            return false;
        }

        logger.info("Connecting to Colibri WebSocket: " + websocketUrl);

        try
        {
            wsClient = new WebSocketClient();
            wsClient.start();

            Future<Session> future = wsClient.connect(this, new URI(websocketUrl));
            wsSession = future.get(CONNECTION_TIMEOUT_MS, TimeUnit.MILLISECONDS);

            logger.info("Colibri WebSocket connected successfully");
            return true;
        }
        catch (Exception e)
        {
            logger.error("Failed to connect to Colibri WebSocket: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * Disconnects from the Colibri WebSocket.
     */
    public void disconnect()
    {
        connected = false;

        if (wsSession != null && wsSession.isOpen())
        {
            try
            {
                wsSession.close();
            }
            catch (Exception e)
            {
                logger.warn("Error closing WebSocket session: " + e.getMessage());
            }
        }

        if (wsClient != null)
        {
            try
            {
                wsClient.stop();
            }
            catch (Exception e)
            {
                logger.warn("Error stopping WebSocket client: " + e.getMessage());
            }
        }

        logger.info("Colibri WebSocket disconnected");
    }

    /**
     * Called when the WebSocket connection is established.
     */
    @OnWebSocketConnect
    public void onConnect(Session session)
    {
        logger.info("Colibri WebSocket onConnect");
        this.wsSession = session;
    }

    /**
     * Called when a text message is received from JVB.
     */
    @OnWebSocketMessage
    public void onMessage(String message)
    {
        if (logger.isDebugEnabled())
        {
            logger.debug("Colibri WebSocket received: " + message);
        }

        try
        {
            JSONObject json = (JSONObject) jsonParser.parse(message);
            String colibriClass = (String) json.get("colibriClass");

            if (colibriClass == null)
            {
                logger.warn("Received message without colibriClass: " + message);
                return;
            }

            switch (colibriClass)
            {
                case "ServerHello":
                    handleServerHello(json);
                    break;

                case "EndpointMessage":
                    handleEndpointMessage(json);
                    break;

                case "DominantSpeakerEndpointChangeEvent":
                    handleDominantSpeakerChange(json);
                    break;

                case "EndpointConnectivityStatusChangeEvent":
                    handleConnectivityStatusChange(json);
                    break;

                case "SenderVideoConstraints":
                    // Ignore - not relevant for transcriber
                    break;

                default:
                    if (logger.isDebugEnabled())
                    {
                        logger.debug("Unhandled colibriClass: " + colibriClass);
                    }
                    break;
            }
        }
        catch (ParseException e)
        {
            logger.error("Failed to parse Colibri WebSocket message: " + e.getMessage());
        }
    }

    /**
     * Handles the ServerHello message from JVB.
     * Responds with ClientHello to complete the handshake.
     */
    @SuppressWarnings("unchecked")
    private void handleServerHello(JSONObject serverHello)
    {
        logger.info("Received ServerHello from JVB");

        // Send ClientHello in response
        JSONObject clientHello = new JSONObject();
        clientHello.put("colibriClass", "ClientHello");

        sendMessage(clientHello.toJSONString());

        // Mark as connected after handshake
        connected = true;
        logger.info("Colibri WebSocket EndpointMessageTransport is now connected");

        // Notify listener
        if (connectionListener != null)
        {
            connectionListener.onConnected();
        }

        // Send initial ReceiverVideoConstraints (we don't need video)
        sendReceiverVideoConstraints();
    }

    /**
     * Handles EndpointMessage from JVB (messages from other participants).
     */
    private void handleEndpointMessage(JSONObject message)
    {
        // EndpointMessages are typically from other participants
        // For transcriber, we mostly ignore these
        if (logger.isDebugEnabled())
        {
            logger.debug("Received EndpointMessage: " + message.toJSONString());
        }
    }

    /**
     * Handles dominant speaker change events.
     */
    private void handleDominantSpeakerChange(JSONObject message)
    {
        String dominantSpeaker = (String) message.get("dominantSpeakerEndpoint");
        if (logger.isDebugEnabled())
        {
            logger.debug("Dominant speaker changed to: " + dominantSpeaker);
        }
    }

    /**
     * Handles endpoint connectivity status changes.
     */
    private void handleConnectivityStatusChange(JSONObject message)
    {
        String endpoint = (String) message.get("endpoint");
        String status = (String) message.get("active");
        if (logger.isDebugEnabled())
        {
            logger.debug("Endpoint " + endpoint + " connectivity: " + status);
        }
    }

    /**
     * Sends ReceiverVideoConstraints to JVB indicating we don't need video.
     */
    @SuppressWarnings("unchecked")
    private void sendReceiverVideoConstraints()
    {
        JSONObject constraints = new JSONObject();
        constraints.put("colibriClass", "ReceiverVideoConstraints");
        constraints.put("lastN", 0); // No video needed for transcriber
        constraints.put("defaultConstraints", new JSONObject());

        sendMessage(constraints.toJSONString());
        logger.info("Sent ReceiverVideoConstraints (lastN=0)");
    }

    /**
     * Sends a message over the WebSocket.
     */
    private void sendMessage(String message)
    {
        if (wsSession == null || !wsSession.isOpen())
        {
            logger.warn("Cannot send message - WebSocket not connected");
            return;
        }

        try
        {
            wsSession.getRemote().sendString(message);
            if (logger.isDebugEnabled())
            {
                logger.debug("Sent Colibri message: " + message);
            }
        }
        catch (Exception e)
        {
            logger.error("Failed to send Colibri message: " + e.getMessage(), e);
        }
    }

    /**
     * Called when the WebSocket connection is closed.
     */
    @OnWebSocketClose
    public void onClose(int statusCode, String reason)
    {
        logger.info("Colibri WebSocket closed: " + statusCode + " - " + reason);
        connected = false;

        if (connectionListener != null)
        {
            connectionListener.onDisconnected(statusCode, reason);
        }
    }

    /**
     * Called when a WebSocket error occurs.
     */
    @OnWebSocketError
    public void onError(Throwable error)
    {
        logger.error("Colibri WebSocket error: " + error.getMessage(), error);
    }

    /**
     * Returns whether the WebSocket is connected and the handshake is complete.
     */
    public boolean isConnected()
    {
        return connected && wsSession != null && wsSession.isOpen();
    }

    /**
     * Listener interface for connection state changes.
     */
    public interface ConnectionListener
    {
        /**
         * Called when the WebSocket is connected and handshake is complete.
         */
        void onConnected();

        /**
         * Called when the WebSocket is disconnected.
         */
        void onDisconnected(int statusCode, String reason);
    }
}
