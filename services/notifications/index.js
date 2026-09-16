const AWSXRay = require('aws-xray-sdk');
const express = require('express');

const app = express();
app.use(express.json());
app.use(AWSXRay.express.openSegment('notifications-service'));

const PORT = process.env.CONTAINER_PORT || 3000;

app.get('/health', (_req, res) => res.status(200).json({ status: 'ok', service: 'notifications' }));

// No ALB path is routed here - this is only reachable service-to-service via
// Cloud Map DNS (notifications.<namespace>), which is why there's no auth
// middleware: only other trusted services inside the VPC can reach port 3000.
app.post('/notify', (req, res) => {
  const { type, userId, orderId } = req.body;
  console.log(`[notification] type=${type} userId=${userId} orderId=${orderId}`);

  // Wire up SES/SNS/etc. here for real delivery. Kept as a log line so the
  // service has zero external dependencies out of the box.
  res.status(202).json({ accepted: true });
});

app.use(AWSXRay.express.closeSegment());

app.listen(PORT, () => console.log(`notifications-service listening on ${PORT}`));
