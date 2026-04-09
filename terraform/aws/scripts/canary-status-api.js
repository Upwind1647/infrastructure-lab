const https = require('https');

const endpoints = [
    process.env.URL_LAB,
    process.env.URL_CLOUD
];

const requestTimeoutMs = 5000;

function checkEndpoint(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, { timeout: requestTimeoutMs }, (response) => {
      response.resume();

      if (response.statusCode !== 200) {
        reject(new Error(`Endpoint ${url} returned status ${response.statusCode}`));
        return;
      }

      resolve();
    });

    request.on('timeout', () => {
      request.destroy(new Error(`Endpoint ${url} timed out after ${requestTimeoutMs}ms`));
    });

    request.on('error', (error) => {
      reject(error);
    });
  });
}

exports.handler = async () => {
  for (const endpoint of endpoints) {
    console.log(`Checking ${endpoint}`);
    await checkEndpoint(endpoint);
  }

  console.log('All endpoint checks passed.');
};
