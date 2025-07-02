console.log('Node.js server.js is running and starting up...');

const express = require('express');
const WebSocket = require('ws');
const cors = require('cors');
const http = require('http');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Middleware
app.use(cors());
app.use(express.json());

// In-memory storage for convoy data
const convoys = new Map(); // convoyId -> convoy data
const userLocations = new Map(); // userId -> location data
const userConnections = new Map(); // userId -> WebSocket connection

// HTTP Routes
app.get('/', (req, res) => {
  res.json({ 
    message: 'Convoy Server Running!',
    status: 'online',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    activeConnections: wss.clients.size,
    activeConvoys: convoys.size,
    activeUsers: userLocations.size
  });
});

// Create a new convoy
app.post('/convoy/create', (req, res) => {
  const { convoyId, creatorId, name } = req.body;
  
  if (!convoyId || !creatorId) {
    return res.status(400).json({ error: 'Missing convoyId or creatorId' });
  }
  
  convoys.set(convoyId, {
    id: convoyId,
    name: name || `Convoy ${convoyId}`,
    creatorId,
    members: [creatorId],
    createdAt: new Date().toISOString(),
    isActive: true
  });
  
  console.log(`🚗 Convoy created: ${convoyId} by ${creatorId}`);
  res.json({ success: true, convoy: convoys.get(convoyId) });
});

// Join a convoy
app.post('/convoy/join', (req, res) => {
  const { convoyId, userId } = req.body;
  
  if (!convoyId || !userId) {
    return res.status(400).json({ error: 'Missing convoyId or userId' });
  }
  
  const convoy = convoys.get(convoyId);
  if (!convoy) {
    return res.status(404).json({ error: 'Convoy not found' });
  }
  
  if (!convoy.members.includes(userId)) {
    convoy.members.push(userId);
  }
  
  console.log(`👥 User ${userId} joined convoy ${convoyId}`);
  res.json({ success: true, convoy });
});

// Get convoy members locations
app.get('/convoy/:convoyId/locations', (req, res) => {
  const { convoyId } = req.params;
  const convoy = convoys.get(convoyId);
  
  if (!convoy) {
    return res.status(404).json({ error: 'Convoy not found' });
  }
  
  const locations = {};
  convoy.members.forEach(memberId => {
    if (userLocations.has(memberId)) {
      locations[memberId] = userLocations.get(memberId);
    }
  });
  
  res.json({ locations });
});

// WebSocket connection handling
wss.on('connection', (ws, req) => {
  console.log('🔌 New WebSocket connection attempt');
  
  // Extract user info from query string
  const url = new URL(req.url, `http://${req.headers.host}`);
  const userId = url.searchParams.get('userId');
  const convoyId = url.searchParams.get('convoyId');
  
  if (!userId) {
    ws.close(1008, 'Missing userId');
    return;
  }
  
  // Store connection
  userConnections.set(userId, ws);
  
  // Join convoy if specified
  if (convoyId) {
    const convoy = convoys.get(convoyId);
    if (convoy && !convoy.members.includes(userId)) {
      convoy.members.push(userId);
    }
  }
  
  console.log(`👤 User ${userId} connected to convoy ${convoyId || 'none'}`);
  
  // Send welcome message
  ws.send(JSON.stringify({
    type: 'connection_established',
    userId,
    convoyId,
    timestamp: new Date().toISOString()
  }));
  
  // Handle incoming messages
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data);
      handleMessage(userId, message);
    } catch (error) {
      console.error('❌ Error parsing message:', error);
    }
  });
  
  // Handle disconnection
  ws.on('close', () => {
    console.log(`👋 User ${userId} disconnected`);
    userConnections.delete(userId);
    
    // Remove from convoy if needed
    if (convoyId) {
      const convoy = convoys.get(convoyId);
      if (convoy) {
        convoy.members = convoy.members.filter(id => id !== userId);
        if (convoy.members.length === 0) {
          convoys.delete(convoyId);
          console.log(`🚗 Convoy ${convoyId} deleted (no members)`);
        }
      }
    }
  });
  
  // Handle errors
  ws.on('error', (error) => {
    console.error(`❌ WebSocket error for user ${userId}:`, error);
  });
});

// Handle different message types
function handleMessage(userId, message) {
  switch (message.type) {
    case 'location_update':
      handleLocationUpdate(userId, message);
      break;
    case 'join_convoy':
      handleJoinConvoy(userId, message);
      break;
    case 'leave_convoy':
      handleLeaveConvoy(userId, message);
      break;
    default:
      console.log(`❓ Unknown message type: ${message.type}`);
  }
}

// Handle location updates (3Hz+)
function handleLocationUpdate(userId, message) {
  const locationData = {
    userId,
    coordinates: message.coordinates,
    velocity: message.velocity || 0,
    heading: message.heading || 0,
    timestamp: message.timestamp || Date.now(),
    accuracy: message.accuracy || 0,
    isOnJourney: message.isOnJourney || false,
    routePoints: message.routePoints || null
  };
  
  // Store location
  userLocations.set(userId, locationData);
  
  // Find user's convoy
  let userConvoyId = null;
  for (const [convoyId, convoy] of convoys) {
    if (convoy.members.includes(userId)) {
      userConvoyId = convoyId;
      break;
    }
  }
  
  if (userConvoyId) {
    // Broadcast to convoy members
    const convoy = convoys.get(userConvoyId);
    convoy.members.forEach(memberId => {
      if (memberId !== userId) {
        const memberWs = userConnections.get(memberId);
        if (memberWs && memberWs.readyState === WebSocket.OPEN) {
          memberWs.send(JSON.stringify({
            type: 'member_location_update',
            convoyId: userConvoyId,
            location: locationData
          }));
        }
      }
    });
  }
  
  console.log(`📍 Location update from ${userId}: [${locationData.coordinates[0].toFixed(6)}, ${locationData.coordinates[1].toFixed(6)}]`);
}

// Handle joining convoy
function handleJoinConvoy(userId, message) {
  const { convoyId } = message;
  const convoy = convoys.get(convoyId);
  
  if (!convoy) {
    const ws = userConnections.get(userId);
    if (ws) {
      ws.send(JSON.stringify({
        type: 'error',
        message: 'Convoy not found'
      }));
    }
    return;
  }
  
  if (!convoy.members.includes(userId)) {
    convoy.members.push(userId);
  }
  
  // Notify convoy members
  convoy.members.forEach(memberId => {
    const memberWs = userConnections.get(memberId);
    if (memberWs && memberWs.readyState === WebSocket.OPEN) {
      memberWs.send(JSON.stringify({
        type: 'member_joined',
        convoyId,
        userId
      }));
    }
  });
  
  console.log(`👥 User ${userId} joined convoy ${convoyId}`);
}

// Handle leaving convoy
function handleLeaveConvoy(userId, message) {
  const { convoyId } = message;
  const convoy = convoys.get(convoyId);
  
  if (convoy) {
    convoy.members = convoy.members.filter(id => id !== userId);
    
    // Notify remaining members
    convoy.members.forEach(memberId => {
      const memberWs = userConnections.get(memberId);
      if (memberWs && memberWs.readyState === WebSocket.OPEN) {
        memberWs.send(JSON.stringify({
          type: 'member_left',
          convoyId,
          userId
        }));
      }
    });
    
    // Delete convoy if empty
    if (convoy.members.length === 0) {
      convoys.delete(convoyId);
      console.log(`🚗 Convoy ${convoyId} deleted (no members)`);
    }
  }
  
  console.log(`👋 User ${userId} left convoy ${convoyId}`);
}

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`🚀 Convoy Server running on port ${PORT}`);
  console.log(`📡 WebSocket server ready for connections`);
  console.log(`🌐 HTTP server: http://localhost:${PORT}`);
  console.log(`🔌 WebSocket: ws://localhost:${PORT}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down convoy server...');
  wss.close(() => {
    server.close(() => {
      console.log('✅ Server shutdown complete');
      process.exit(0);
    });
  });
}); 