// Responsive COD-style movement tuned for a mobile browser: quick starts,
// readable acceleration, tactical sprint, controllable slides, and forgiving jumps.
export const MOVEMENT_SETTINGS = Object.freeze({
  walkSpeed: 300,
  sprintSpeed: 450,
  tacticalSprintSpeed: 505,
  crouchSpeed: 170,
  proneSpeed: 92,

  groundAcceleration: 3600,
  groundDeceleration: 3200,
  airAcceleration: 1450,
  friction: 7.2,

  slideSpeed: 485,
  slideDuration: 0.62,
  slideCooldown: 0.16,
  slideFriction: 1.05,
  slideSteer: 0.48,
  slideMinSpeed: 285,
  slideExitSpeed: 205,

  gravity: 1050,
  jumpVelocity: 330,
  coyoteTime: 0.10,
  jumpBufferTime: 0.12,
  airControl: 0.82,
  maxAirSpeed: 465,
  slideHopBoost: 1.025,

  sprintFovBoost: 3.5,
  tacticalSprintFovBoost: 6,
  slideFovBoost: 5,
  cameraSmoothing: 16,
  slideCameraDrop: 8,
  landingDip: 1.35,
});
